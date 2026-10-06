/* SPDX-License-Identifier: Apache-2.0
 * Original experiment-only LP64 adapter; DGTSV source is separately licensed.
 * One owner supplies stable Bigarray scratch. No pointer retention, OCaml
 * callback/allocation, runtime unlock, thread creation or global FP changes.
 */
#include <stdint.h>
#include <stddef.h>
#include <limits.h>
#include <float.h>
#include <math.h>
#include <fenv.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <caml/custom.h>
/* Pinned OCaml 5.3 runtime identity for malformed-FFI controls; internal ABI. */
extern const struct custom_operations caml_ba_ops;
_Static_assert(sizeof(int)==4 && sizeof(double)==8 && DBL_MANT_DIG==53, "LP64 binary64 ABI required");
#if defined(__x86_64__)
#include <xmmintrin.h>
#endif
extern void dgtsv_(const int *, const int *, double *, double *, double *, double *, const int *, int *);
/* The wrapper validates dimensions before entry. Retain LAPACK INFO instead
 * of linking its process-terminating Fortran error printer. No DGTSV edit. */
void xerbla_(const char *name, const int *info, size_t len) {(void)name;(void)info;(void)len;}
static int environment_ok(void) {
  if(fegetround()!=FE_TONEAREST) return 0;
#if defined(__aarch64__)
  uint64_t fpcr; __asm__ volatile("mrs %0, fpcr":"=r"(fpcr));
  if(fpcr & ((UINT64_C(1)<<24)|(UINT64_C(1)<<19)|(UINT64_C(1)<<0))) return 0;
#elif defined(__x86_64__)
  if(_mm_getcsr() & ((1u<<15)|(1u<<6))) return 0;
#else
  return 0;
#endif
  return 1;
}
static int floats(value a, mlsize_t n) {
  return Is_block(a) && Tag_val(a)==Double_array_tag && Wosize_val(a)/Double_wosize==n;
}
CAMLprim value morphiq_experiment_dgtsv(value bands,value mask,value workspace) {
  CAMLparam3(bands,mask,workspace);
  if(!Is_block(bands)||Tag_val(bands)!=0||Wosize_val(bands)!=9)
    caml_invalid_argument("DGTSV bands");
  value first=Field(bands,0);
  if(!Is_block(first)||Tag_val(first)!=Double_array_tag) caml_invalid_argument("DGTSV floats");
  mlsize_t count=Wosize_val(first)/Double_wosize;
  if(count<3||count>8192||count-2>INT_MAX) caml_invalid_argument("DGTSV LP64 size");
  for(int k=0;k<9;k++) {
    if(!floats(Field(bands,k),count)) caml_invalid_argument("DGTSV shape");
    for(int j=0;j<k;j++) if(Field(bands,k)==Field(bands,j)) caml_invalid_argument("DGTSV alias");
  }
  if(!Is_block(mask)||Tag_val(mask)!=0||Wosize_val(mask)!=count) caml_invalid_argument("DGTSV mask");
  for(mlsize_t i=0;i<count;i++) if(Field(mask,i)!=Val_true&&Field(mask,i)!=Val_false) caml_invalid_argument("DGTSV mask value");
  /* Normal callers have a typed Bigarray; confirm the custom operations before
   * dereferencing its descriptor, including malicious malformed FFI controls. */
  if(!Is_block(workspace)||Tag_val(workspace)!=Custom_tag||Custom_ops_val(workspace)!=&caml_ba_ops)
    caml_invalid_argument("DGTSV workspace type");
  struct caml_ba_array *ba=Caml_ba_array_val(workspace);
  int n=(int)count-2;
  if(ba->num_dims!=1||(ba->flags&CAML_BA_KIND_MASK)!=CAML_BA_FLOAT64||
     (ba->flags&CAML_BA_LAYOUT_MASK)!=CAML_BA_C_LAYOUT||ba->dim[0]!=4*n)
    caml_invalid_argument("DGTSV workspace shape");
  fenv_t saved;
  if(fegetenv(&saved)!=0) caml_failwith("DGTSV fegetenv");
  if(!environment_ok()) caml_invalid_argument("DGTSV floating-point environment");
  double *dl=ba->data,*d=dl+n,*du=d+n,*b=du+n;
  int result=0;
  for(int j=0;j<n;j++) {
    int i=j+1,take=Bool_val(Field(mask,i));
    dl[j]=(j==0||take)?0.:Double_field(Field(bands,0),i);
    d[j]=Double_field(Field(bands,6),i);
    du[j]=(j==n-1||take)?0.:Double_field(Field(bands,2),i);
    b[j]=Double_field(Field(bands,7),i);
    if(!isfinite(dl[j])||!isfinite(d[j])||!isfinite(du[j])||!isfinite(b[j])) {result=6;goto done;}
  }
  /* DL[j] belongs to row j; LAPACK packs subdiagonal as DL[0]=A[1,0]. */
  for(int j=0;j<n-1;j++) dl[j]=dl[j+1];
  int rhs=1,info=0;
  dgtsv_(&n,&rhs,dl,d,du,b,&n,&info);
  if(info<0) {result=7;goto done;}
  if(info>0) {result=5;goto done;}
  for(int j=0;j<n;j++) if(!isfinite(b[j])) {result=6;goto done;}
  for(int j=0;j<n;j++) Store_double_field(Field(bands,8),j+1,b[j]);
done:
  if(fesetenv(&saved)!=0) caml_failwith("DGTSV fesetenv");
  CAMLreturn(Val_int(result));
}
CAMLprim value morphiq_experiment_rounding(value mode) {
  int old=fegetround();
  if(Long_val(mode)>=0) {
    int next=Long_val(mode)==0?FE_TONEAREST:FE_UPWARD;
    if(fesetround(next)!=0) caml_failwith("rounding control");
  }
  return Val_int(old==FE_TONEAREST?0:old==FE_UPWARD?1:2);
}
CAMLprim value morphiq_experiment_flush(value mode) {
  int old;
#if defined(__aarch64__)
  uint64_t word; __asm__ volatile("mrs %0, fpcr":"=r"(word));
  uint64_t mask=(UINT64_C(1)<<24);old=(word&mask)!=0;
  if(Long_val(mode)>=0) {word=Long_val(mode)?word|mask:word&~mask;__asm__ volatile("msr fpcr, %0"::"r"(word));}
#elif defined(__x86_64__)
  unsigned word=_mm_getcsr(),mask=1u<<15;old=(word&mask)!=0;
  if(Long_val(mode)>=0) _mm_setcsr(Long_val(mode)?word|mask:word&~mask);
#else
  caml_failwith("unsupported environment control");
#endif
  return Val_int(old);
}
CAMLprim value morphiq_experiment_flags(value action) {
  int old=fetestexcept(FE_ALL_EXCEPT),next=Long_val(action);
  if(next==0) feclearexcept(FE_ALL_EXCEPT);
  else if(next>0) feraiseexcept(next&FE_ALL_EXCEPT);
  return Val_int(old);
}
