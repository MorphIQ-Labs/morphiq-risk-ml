/* RN(a b) in binary64. A lone multiply has nothing to contract with. */
#include <caml/mlvalues.h>
#include <caml/alloc.h>

double morphiq_fp_mul(double a, double b) { return a * b; }

value morphiq_fp_mul_byte(value a, value b)
{
  return caml_copy_double(Double_val(a) * Double_val(b));
}
