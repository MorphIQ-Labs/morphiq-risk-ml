/* SPDX-License-Identifier: Apache-2.0
 * Original project implementation of the frozen OCaml policy operation graph.
 * No contraction/reassociation, callbacks, allocation, retained pointers,
 * runtime-lock release, thread creation or floating-point environment changes.
 */
#include <math.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>

static int float_band(value a, mlsize_t n) {
  return Is_block(a) && Tag_val(a) == Double_array_tag &&
    Wosize_val(a) / Double_wosize == n;
}
static int word_array(value a, mlsize_t n) {
  return Is_block(a) && Tag_val(a) == 0 && Wosize_val(a) == n;
}
static void invalid(void) {
  caml_invalid_argument("American policy kernel shape, range or alias");
}

CAMLprim value morphiq_american_policy(value bands, value flags, value state,
                                     value first_arg, value last_arg) {
  CAMLparam5(bands, flags, state, first_arg, last_arg);
  if (!word_array(bands, 9) || !word_array(flags, 2) ||
      !word_array(state, 5) || !Is_long(first_arg) || !Is_long(last_arg)) invalid();
  for (int k = 0; k < 5; ++k) if (!Is_long(Field(state, k))) invalid();
  value first_band = Field(bands, 0);
  if (!Is_block(first_band) || Tag_val(first_band) != Double_array_tag) invalid();
  mlsize_t n = Wosize_val(first_band) / Double_wosize;
  for (int k = 0; k < 9; ++k) {
    if (!float_band(Field(bands, k), n)) invalid();
    for (int j = 0; j < k; ++j)
      if (Field(bands, k) == Field(bands, j)) invalid();
  }
  value mask = Field(flags, 0), oldmask = Field(flags, 1);
  if (!word_array(mask, n) || !word_array(oldmask, n) || mask == oldmask ||
      mask == bands || mask == flags || mask == state ||
      oldmask == bands || oldmask == flags || oldmask == state) invalid();
  intnat phase = Long_val(Field(state, 0));
  intnat obstacle = Long_val(Field(state, 1));
  intnat changed = Long_val(Field(state, 2));
  intnat first = Long_val(first_arg), last = Long_val(last_arg);
  if (n < 3 || phase < 0 || phase > 3 || (obstacle != 0 && obstacle != 1) ||
      (changed != 0 && changed != 1) || first < 1 || last < 1 ||
      (uintnat)first >= n - 1 || (uintnat)last >= n - 1 ||
      (phase == 2 ? (last > first || first - last >= 256)
                  : (first > last || last - first >= 256)) ||
      (phase == 1 && first < 2)) invalid();
  /* Validate mask immediates before any output write, including predecessor. */
  intnat low = phase == 2 ? last : first;
  intnat high = phase == 2 ? first : last;
  for (intnat i = low - (phase == 1); i <= high; ++i)
    if (Field(mask, i) != Val_false && Field(mask, i) != Val_true) invalid();

  value lo = Field(bands, 0), diag = Field(bands, 1), hi = Field(bands, 2);
  value rhs = Field(bands, 3), v = Field(bands, 4), g = Field(bands, 5);
  value d = Field(bands, 6), z = Field(bands, 7), candidate = Field(bands, 8);
  /* Unsigned wrap followed by Val_long discards the tag bit: exactly OCaml
     immediate-integer modular multiplication/XOR, without signed C overflow. */
  uintnat fingerprint = (uintnat)Long_val(Field(state, 3));
  intnat visited = 0, status = 0, direction = phase == 2 ? -1 : 1;
  for (intnat i = first; ; i += direction) {
    ++visited;
    if (phase == 0) {
      Field(oldmask, i) = Field(mask, i);
      double pvalue = fma(Double_field(lo, i), Double_field(v, i - 1),
        fma(Double_field(diag, i), Double_field(v, i),
          fma(Double_field(hi, i), Double_field(v, i + 1), -Double_field(rhs, i))));
      if (!isfinite(pvalue)) { status = 1; break; }
      int take = obstacle && pvalue > Double_field(v, i) - Double_field(g, i);
      Field(mask, i) = Val_bool(take);
      fingerprint = fingerprint * (uintnat)65599 ^ (uintnat)(take ? i : -i);
      if (Field(mask, i) != Field(oldmask, i)) changed = 1;
      Store_double_field(d, i, take ? 1. : Double_field(diag, i));
      Store_double_field(z, i, take ? Double_field(g, i) : Double_field(rhs, i));
    } else if (phase == 1) {
      if (Double_field(d, i - 1) <= 0.) { status = 2; break; }
      double mult = Bool_val(Field(mask, i)) ? 0. : Double_field(lo, i) / Double_field(d, i - 1);
      double prev_hi = Bool_val(Field(mask, i - 1)) ? 0. : Double_field(hi, i - 1);
      double pivot = Double_field(d, i) - mult * prev_hi;
      if (!isfinite(pivot)) { status = 3; break; }
      Store_double_field(d, i, pivot);
      double solved_rhs = Double_field(z, i) - mult * Double_field(z, i - 1);
      if (!isfinite(solved_rhs)) { status = 4; break; }
      Store_double_field(z, i, solved_rhs);
    } else if (phase == 2) {
      if (Double_field(d, i) <= 0.) { status = 5; break; }
      double next = ((uintnat)i == n - 2 || Bool_val(Field(mask, i))) ? 0.
        : Double_field(hi, i) * Double_field(candidate, i + 1);
      double solution = (Double_field(z, i) - next) / Double_field(d, i);
      if (!isfinite(solution)) { status = 6; break; }
      Store_double_field(candidate, i, solution);
    } else {
      Store_double_field(v, i, Double_field(candidate, i));
    }
    if (i == last) break;
  }
  Field(state, 2) = Val_long(changed);
  Field(state, 3) = Val_long(fingerprint);
  Field(state, 4) = Val_long(visited);
  CAMLreturn(Val_long(status));
}
