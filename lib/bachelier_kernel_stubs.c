/* Operation-preserving Bachelier middle branch.
 * Y-prime coefficients/operation grouping derive from lib/normalised_black.ml.
 * Peter Jaeckel's full notice is retained in LICENSES/LetsBeRational.txt and
 * bachelier_kernel_NOTICE.txt alongside this file. Elementary exp follows lib/elementary.ml;
 * its Sun notice is also retained in bachelier_kernel_NOTICE.txt. No SLEEF source is vendored.
 */
#if defined(__aarch64__)
#include <arm_neon.h>
#endif
#include <math.h>
#include <stdint.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

/* Template instantiations intentionally use identical expression grouping.
 * Auto-vectorization is disabled so the scalar C control stays scalar. */
#define T double
#define C(x) (x)
#define F(a,b,c) fma((a),(b),(c))
#define FLOOR(x) floor(x)
#define ROUND(x) round(x)
#define SCALE(x,n) ldexp((x),(int)(n))
#define FN(x) scalar_##x
#define EXP(x) scalar_exp(x)
#include "bachelier_operation_graph.h"
#undef T
#undef C
#undef F
#undef FLOOR
#undef ROUND
#undef SCALE
#undef FN
#undef EXP

#if defined(__aarch64__)
static inline float64x2_t scale_v(float64x2_t x,float64x2_t n) {
  int64x2_t k=vcvtq_s64_f64(n);
  uint64x2_t e=vreinterpretq_u64_s64(vshlq_n_s64(vaddq_s64(k,vdupq_n_s64(1023)),52));
  return x*vreinterpretq_f64_u64(e);
}
#define T float64x2_t
#define C(x) vdupq_n_f64(x)
#define F(a,b,c) vfmaq_f64((c),(a),(b))
#define FLOOR(x) vrndmq_f64(x)
#define ROUND(x) vrndaq_f64(x)
#define SCALE(x,n) scale_v((x),(n))
#define FN(x) vector_##x
#define EXP(x) vector_exp(x)
#include "bachelier_operation_graph.h"

#endif

/* All parameters originate from the private OCaml middle-branch preparation.
 * No allocation, callbacks, pointer retention or runtime-lock release occurs
 * while the flat-array data pointers are borrowed. NEON loads allow unaligned
 * vector addresses. An odd final row executes the identical scalar graph. */
CAMLprim value morphiq_bachelier_kernel(value kind, value params, value result) {
  CAMLparam3(kind,params,result);
  intnat mode=Long_val(kind);
  mlsize_t n=Wosize_val(result)/Double_wosize;
  if (mode<1 || mode>2 ||
      (Wosize_val(result) && Tag_val(result)!=Double_array_tag) ||
      (Wosize_val(params) && Tag_val(params)!=Double_array_tag) ||
      Wosize_val(params)/Double_wosize != 4*n)
    caml_invalid_argument("Bachelier kernel shape or mode");
  const double *p=(const double*)params;
  double *out=(double*)result;
  mlsize_t i=0;
#if defined(__aarch64__)
  if(mode==2) {
    for(;i+1<n;i+=2) {
      float64x2_t y=vector_price(vld1q_f64(p+i),vld1q_f64(p+n+i),vld1q_f64(p+2*n+i),vld1q_f64(p+3*n+i));
      vst1q_f64(out+i,y);
    }
  }
#endif
  for(;i<n;i++) out[i]=scalar_price(p[i],p[n+i],p[2*n+i],p[3*n+i]);
  CAMLreturn(Val_unit);
}

CAMLprim value morphiq_bachelier_backend(value unit) {
  (void)unit;
#if !defined(FLAT_FLOAT_ARRAY)
  return Val_int(0);
#elif defined(__aarch64__)
  return Val_int(2);
#else
  return Val_int(1);
#endif
}
