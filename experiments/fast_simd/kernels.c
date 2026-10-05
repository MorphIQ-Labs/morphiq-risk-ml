/* Experimental operation-preserving Bachelier middle branch.
 * Y-prime coefficients/operation grouping derive from lib/normalised_black.ml.
 * Peter Jaeckel's full notice is retained in LICENSES/LetsBeRational.txt and
 * NOTICE.txt alongside this file. Elementary exp follows lib/elementary.ml;
 * its Sun notice is also retained in NOTICE.txt. No SLEEF source is vendored.
 */
#include <arm_neon.h>
#include <math.h>
#include <stdint.h>
#include <time.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <sleef.h>

/* Template instantiations intentionally use identical expression grouping.
 * Auto-vectorization is disabled so the scalar C control stays scalar. */
#define T double
#define C(x) (x)
#define F(a,b,c) fma((a),(b),(c))
#define FLOOR(x) floor(x)
#define ROUND(x) round(x)
#define SCALE(x,n) ldexp((x),(int)(n))
#define FN(x) scalar_##x
#define EXP(x,mode) scalar_exp(x)
#include "operation_graph.h"
#undef T
#undef C
#undef F
#undef FLOOR
#undef ROUND
#undef SCALE
#undef FN
#undef EXP

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
#define EXP(x,mode) ((mode)==3 ? Sleef_expd2_u10advsimd(x) : vector_exp(x))
#include "operation_graph.h"

CAMLprim value morphiq_simd_kernel(value kind, value params, value result) {
  CAMLparam3(kind,params,result);
  int mode=Int_val(kind);
  mlsize_t n=Wosize_val(result)/Double_wosize;
  if (mode<1 || mode>3 || Wosize_val(params)/Double_wosize != 4*n || n%2)
    caml_invalid_argument("SIMD kernel shape or mode");
  double *p= (double*)params, *out=(double*)result;
  if(mode==1) {
    for(mlsize_t i=0;i<n;i++) out[i]=scalar_price(p[i],p[n+i],p[2*n+i],p[3*n+i],mode);
  } else {
    for(mlsize_t i=0;i<n;i+=2) {
      float64x2_t y=vector_price(vld1q_f64(p+i),vld1q_f64(p+n+i),vld1q_f64(p+2*n+i),vld1q_f64(p+3*n+i),mode);
      vst1q_f64(out+i,y);
    }
  }
  CAMLreturn(Val_unit);
}
CAMLprim value morphiq_simd_clock(value unit) {
  CAMLparam1(unit);
  struct timespec t;
  if(clock_gettime(CLOCK_MONOTONIC,&t)) caml_failwith("clock_gettime");
  CAMLreturn(caml_copy_double((double)t.tv_sec+1e-9*(double)t.tv_nsec));
}
