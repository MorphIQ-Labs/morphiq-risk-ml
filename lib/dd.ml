(* Double-double arithmetic: a value is the unevaluated sum hi + lo with
   |lo| <= ulp(hi)/2 (Dekker 1971; Hida, Li and Bailey's QD library). Only
   what the log-moneyness needs is provided. *)

type t = { hi : float; lo : float }

let of_float hi = { hi; lo = 0.0 }

let renormalise hi lo =
  let s = hi +. lo in
  { hi = s; lo = lo -. (s -. hi) }

let add a b =
  let s, e = Split.two_sum a.hi b.hi in
  let t, f = Split.two_sum a.lo b.lo in
  let { hi; lo } = renormalise s (e +. t) in
  renormalise hi (lo +. f)

let neg a = { hi = -.a.hi; lo = -.a.lo }
let sub a b = add a (neg b)

let two_prod a b =
  let p = a *. b in
  { hi = p; lo = Float.fma a b (-.p) }

let mul a b =
  let p = two_prod a.hi b.hi in
  renormalise p.hi (p.lo +. ((a.hi *. b.lo) +. (a.lo *. b.hi)))

let mul_float a f =
  let p = two_prod a.hi f in
  renormalise p.hi (p.lo +. (a.lo *. f))

let div a b =
  let q1 = a.hi /. b.hi in
  let r = sub a (mul_float b q1) in
  let q2 = r.hi /. b.hi in
  let r = sub r (mul_float b q2) in
  let q3 = r.hi /. b.hi in
  add (renormalise q1 q2) (of_float q3)

let to_float a = a.hi +. a.lo

(* ln 2 = ln2_hi + ln2_lo to 106 bits. *)
let ln2 = { hi = 0x1.62e42fefa39efp-1; lo = 0x1.abc9e3b39803fp-56 }
let sqrt_half = 0x1.6a09e667f3bcdp-1

(* 1/(2k+1) for the atanh series, to double-double precision. *)
let series_terms = 22
let reciprocals = Array.init (series_terms + 1) (fun k -> div (of_float 1.0) (of_float (float (2 * k + 1))))

(* ln m for m in [sqrt 1/2, sqrt 2]: 2 atanh u, u = (m-1)/(m+1), |u| <= 0.1716,
   so u^2 <= 0.0295 and 22 terms of sum u^(2k)/(2k+1) reach 2^-106. *)
let log_reduced m =
  let u = div (of_float (m -. 1.0)) (add (of_float m) (of_float 1.0)) in
  let v = mul u u in
  let acc = ref reciprocals.(series_terms) in
  for k = series_terms - 1 downto 0 do
    acc := add (mul !acc v) reciprocals.(k)
  done;
  mul_float (mul u !acc) 2.0

(* ln a for a positive, finite, normal a. *)
let log_float a =
  let m, e = Float.frexp a in
  let m, e = if m < sqrt_half then (2.0 *. m, e - 1) else (m, e) in
  add (log_reduced m) (mul_float ln2 (float e))
