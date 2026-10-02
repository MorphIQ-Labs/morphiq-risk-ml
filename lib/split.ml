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
  (* The cutoff must include the prefactor exponent: a large m can rescue
     exp(-hi) from underflow. Normalize extreme prefactors so the reduced
     product also stays normal until the final ldexp. *)
  let magnitude = Float.abs m in
  let mantissa, exponent, ceiling_exponent =
    if magnitude >= 0x1p-400 && magnitude <= 0x1p400 then (m, 0, 401)
    else
      let f, e = Float.frexp m in
      (f, e, e)
  in
  if hi > (1077.0 +. float (ceiling_exponent + k)) *. ln2_hi then 0.0 *. m
  else
    let n = Float.floor (hi /. ln2_hi) in
    let r = Float.fma (-.n) ln2_hi hi -. (n *. ln2_lo) in
    Float.ldexp
      (mantissa *. (Elementary.exp (-.r) *. (1.0 -. lo)))
      (k + exponent - int_of_float n)

(* sqrt t = hi + lo to first order (one Newton correction from the exact
   residual t - hi^2). *)
let sqrt t =
  if t <= 0.0 || not (Float.is_finite t) then (Float.sqrt t, 0.0)
  else
    let k =
      if t >= 0x1p-400 && t <= 0x1p400 then 0
      else (snd (Float.frexp t) - 1) asr 1
    in
    let scaled = if k = 0 then t else Float.ldexp t (-2 * k) in
    let hi = Float.sqrt scaled in
    let lo = Float.fma (-.hi) hi scaled /. (2.0 *. hi) in
    if k = 0 then (hi, lo) else (Float.ldexp hi k, Float.ldexp lo k)

(* (n + nl) / (d + dl) = q + r to first order, for normalized input pairs. *)
let quotient_dd n nl d dl =
  let reduced n nl d dl =
    let q = n /. d in
    (* The correction includes both input low words and can exceed half an
       ulp of q. Since |r| <= 4u|q|, Fast2Sum restores the nonoverlap
       required by DD consumers exactly. *)
    let r = (Float.fma (-.q) d n +. nl -. (q *. dl)) /. d in
    let hi = q +. r in
    (hi, r -. (hi -. q))
  in
  let ordinary x = Float.abs x >= 0x1p-400 && Float.abs x <= 0x1p400 in
  if (n = 0.0 || ordinary n) && ordinary d then reduced n nl d dl
  else if d = 0.0 || not (Float.is_finite n && Float.is_finite d) then
    reduced n nl d dl
  else
    (* A normal quotient does not ensure a representable fma residual.
       Normalize before forming it, just as in Dd.div. *)
    let en = snd (Float.frexp n) - 1 and ed = snd (Float.frexp d) - 1 in
    let q, r =
      reduced (Float.ldexp n (-en)) (Float.ldexp nl (-en)) (Float.ldexp d (-ed))
        (Float.ldexp dl (-ed))
    in
    (Float.ldexp q (en - ed), Float.ldexp r (en - ed))

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
