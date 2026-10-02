(* Error-free transformations and an exponential that takes its argument as
   an unevaluated sum, so rounding in a large exponent is not amplified. *)

(* Knuth's TwoSum: a + b = s + e exactly. *)
let two_sum a b =
  let s = a +. b in
  let bb = s -. a in
  (s, a -. (s -. bb) +. (b -. bb))

(* u^2 = hi + lo exactly. *)
let square u =
  let hi = u *. u in
  (hi, Float.fma u u (-.hi))

let ln2_hi = 0x1.62e42fefa39efp-1
let ln2_lo = 0x1.abc9e3b39803fp-56

(* 2^k * m * exp(-(hi + lo)) for hi >= 0 and |lo| <= ulp(hi), rounded once.
   exp(-hi) is reduced to 2^-n exp(-r) with r = hi - n ln 2 in [0, ln 2)
   (Cody-Waite with a two-part ln 2), so neither the exponential nor the
   product leaves the normal range before the final ldexp. exp(-lo) is taken
   to first order, exact to within lo^2. *)
let scaled_exp_neg ?(k = 0) m hi lo =
  (* |m| < 2^1024 and exp(-r) <= 1, so past 2^-(1100 - k) the result is zero. *)
  if hi > (1100.0 +. float k) *. ln2_hi then 0.0 *. m
  else
    let n = Float.floor (hi /. ln2_hi) in
    let r = Float.fma (-.n) ln2_hi hi -. (n *. ln2_lo) in
    Float.ldexp (m *. (Elementary.exp (-.r) *. (1.0 -. lo))) (k - int_of_float n)

(* sqrt t = hi + lo to first order (one Newton correction from the exact
   residual t - hi^2). *)
let sqrt t =
  let hi = Float.sqrt t in
  if hi = 0.0 || not (Float.is_finite hi) then (hi, 0.0) else (hi, Float.fma (-.hi) hi t /. (2.0 *. hi))

(* (n + nl) / (d + dl) = q + r to first order, for |nl| <= ulp(n), |dl| <= ulp(d). *)
let quotient_dd n nl d dl =
  let q = n /. d in
  (q, (Float.fma (-.q) d n +. nl -. (q *. dl)) /. d)

(* q = n / d with its remainder: n / d = q + r exactly to first order. *)
let quotient n d =
  let q = n /. d in
  (q, Float.fma (-.q) d n /. d)

(* 2^k * a1 * a2 * ... with one final rounding into the subnormals: the
   mantissas (each in [1/2, 1)) are multiplied and the exponents summed. *)
let product_ldexp factors k =
  let m, e =
    List.fold_left
      (fun (m, e) a ->
        let fm, fe = Float.frexp a in
        let pm, pe = Float.frexp (m *. fm) in
        (pm, e + fe + pe))
      (1.0, k) factors
  in
  Float.ldexp m e
