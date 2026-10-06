/* SPDX-License-Identifier: Apache-2.0
 * Original project implementation of Early_exercise's residual operation graph.
 * Compile without contraction/reassociation/vectorization. Only explicit fma
 * fuses operations; multiplication in the magnitude sum rounds separately.
 */
#include <math.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>

static double selected_max(double a, double b) { return a >= b ? a : b; }
static double selected_min(double a, double b) { return a <= b ? a : b; }
static int float_array(value a, mlsize_t n) {
  return Is_block(a) && Tag_val(a) == Double_array_tag &&
    Wosize_val(a) / Double_wosize == n;
}

CAMLprim value morphiq_american_residual(value bands, value first_arg,
    value last_arg, value metrics, value indices) {
  CAMLparam5(bands, first_arg, last_arg, metrics, indices);
  if (!Is_block(bands) || Tag_val(bands) != 0 || Wosize_val(bands) != 6 ||
      !float_array(metrics, 2) || !Is_block(indices) || Tag_val(indices) != 0 ||
      Wosize_val(indices) != 3 || !Is_long(first_arg) || !Is_long(last_arg) ||
      !Is_long(Field(indices, 0)) || !Is_long(Field(indices, 1)) ||
      !Is_long(Field(indices, 2)))
    caml_invalid_argument("American residual kernel shape or range");
  value first_band = Field(bands, 0);
  if (!Is_block(first_band) || Tag_val(first_band) != Double_array_tag)
    caml_invalid_argument("American residual kernel shape or range");
  mlsize_t n = Wosize_val(first_band) / Double_wosize;
  for (int k = 0; k < 6; ++k)
    if (!float_array(Field(bands, k), n))
      caml_invalid_argument("American residual kernel shape or range");
  intnat first = Long_val(first_arg), last = Long_val(last_arg);
  intnat obstacle = Long_val(Field(indices, 0));
  intnat worst_row = Long_val(Field(indices, 1));
  if (n < 3 || first < 1 || last < first || (uintnat)last >= n - 1 ||
      last - first >= 256 || (obstacle != 0 && obstacle != 1) ||
      worst_row < 0 || (uintnat)worst_row >= n)
    caml_invalid_argument("American residual kernel shape or range");

  /* Checked shapes/ranges; no allocation, callbacks, lock release, or retained
     pointers from here to return. Inputs are read-only; state is disjoint by
     construction and shape (two floats / three immediate integers). */
  value lo = Field(bands, 0), diag = Field(bands, 1), hi = Field(bands, 2);
  value rhs = Field(bands, 3), v = Field(bands, 4), g = Field(bands, 5);
  double worst = Double_field(metrics, 0), indicator = Double_field(metrics, 1);
  intnat visited = 0, status = 0;
  for (intnat i = first; i <= last; ++i) {
    ++visited;
    double pvalue = fma(Double_field(lo, i), Double_field(v, i - 1),
      fma(Double_field(diag, i), Double_field(v, i),
        fma(Double_field(hi, i), Double_field(v, i + 1), -Double_field(rhs, i))));
    double e = Double_field(v, i) - Double_field(g, i);
    double r = obstacle ? selected_max(fabs(selected_min(pvalue, e)),
      selected_max(-pvalue, -e)) : fabs(pvalue);
    if (!isfinite(r)) { status = 1; break; }
    if (r > worst) { worst = r; worst_row = i; }
    double magnitude = fabs(Double_field(lo, i) * Double_field(v, i - 1));
    magnitude = magnitude + fabs(Double_field(diag, i) * Double_field(v, i));
    magnitude = magnitude + fabs(Double_field(hi, i) * Double_field(v, i + 1));
    magnitude = magnitude + fabs(Double_field(rhs, i));
    magnitude = magnitude + fabs(Double_field(v, i));
    magnitude = magnitude + fabs(Double_field(g, i));
    double screen = (0x1p-48 * magnitude) + (32. * 0x0.0000000000001p-1022);
    if (!isfinite(screen)) { status = 2; break; }
    indicator = selected_max(indicator, screen);
  }
  Store_double_field(metrics, 0, worst);
  Store_double_field(metrics, 1, indicator);
  Field(indices, 1) = Val_long(worst_row);
  Field(indices, 2) = Val_long(visited);
  CAMLreturn(Val_long(status));
}
