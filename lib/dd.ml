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
let scale a k = { hi = Float.ldexp a.hi k; lo = Float.ldexp a.lo k }
let compare_float a f = if a.hi <> f then compare a.hi f else compare a.lo 0.0

(* exp and expm1 follow the QD library's dd_real (Hida, Li and Bailey,
   qd-2.3.24, dd_real.cpp), with its reduction constant k = 512 and its
   stopping rule. One departure: exp covers the binary64 range down to the
   subnormals (QD returns 0 below -709), where the result's low part
   underflows and the precision falls toward binary64's. *)

(* 1/n! for n = 3..17, as double-doubles. *)
let inverse_factorials =
  let a = Array.make 18 (of_float 1.0) in
  for n = 1 to 17 do
    a.(n) <- div a.(n - 1) (of_float (float n))
  done;
  Array.sub a 3 15

let inv_k = 1.0 /. 512.0

(* e^(512 r) - 1 for the reduced r = (x - m ln 2)/512: the Taylor series of
   e^r - 1 until a term falls below 2^-104/512 (QD's dd_real::_eps), then
   nine doublings
   s <- 2s + s^2, each of which maps e^y - 1 to e^(2y) - 1 exactly. *)
let expm1_reduced r =
  let p = mul r r in
  let s = ref (add r (scale p (-1))) in
  let p = ref (mul p r) in
  let t = ref (mul !p inverse_factorials.(0)) in
  let i = ref 0 in
  let continue = ref true in
  while !continue do
    s := add !s !t;
    p := mul !p r;
    incr i;
    t := mul !p inverse_factorials.(!i);
    continue := Float.abs (to_float !t) > inv_k *. 0x1p-104 && !i < 5
  done;
  s := add !s !t;
  for _ = 1 to 9 do
    s := add (scale !s 1) (mul !s !s)
  done;
  !s

let exp x =
  if x.hi < -745.2 then of_float 0.0
  else if x.hi > 709.8 then of_float Float.infinity
  else if x.hi = 0.0 then of_float 1.0
  else
    let m = Float.floor ((x.hi /. ln2.hi) +. 0.5) in
    let r = scale (sub x (mul_float ln2 m)) (-9) in
    scale (add (expm1_reduced r) (of_float 1.0)) (int_of_float m)

(* e^x - 1. For |x| <= ln 2 / 2 the reduction has m = 0 and the doubled
   series is e^x - 1 itself, with no cancellation against 1. *)
let expm1 x =
  if Float.abs x.hi <= 0.34657359027997264 then expm1_reduced (scale x (-9))
  else sub (exp x) (of_float 1.0)

let sqrt_half = 0x1.6a09e667f3bcdp-1

(* 1/(2k+1) for the atanh series, to double-double precision. *)
let series_terms = 22

let reciprocals =
  Array.init (series_terms + 1) (fun k ->
      div (of_float 1.0) (of_float (float ((2 * k) + 1))))

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

(* 2^k (hi + lo), correctly rounded to binary64, including into the
   subnormals, where ldexp of the rounded sum would round twice. On the
   subnormal grid (quantum 2^-1074) the scaled value is an integer part and
   a fraction; the fraction is compared with 1/2 exactly, the low part
   breaks an exact tie, and a true tie goes to even. *)
let to_float_scaled a k =
  let v = Float.ldexp a.hi k in
  if Float.abs v >= Float.min_float || a.hi = 0.0 || not (Float.is_finite v)
  then Float.ldexp (to_float a) k
  else
    let shift = k + 1074 in
    let u = Float.ldexp a.hi shift and ul = Float.ldexp a.lo shift in
    let s, e = Split.two_sum u ul in
    let f = Float.floor s in
    (* s - f is exact, and when it is not exactly 1/2 it differs from 1/2 by at
       least ulp(s) > |e|, so only an exact tie consults e. *)
    let g = s -. f in
    let n =
      if g > 0.5 || (g = 0.5 && e > 0.0) then f +. 1.0
      else if g < 0.5 || (g = 0.5 && e < 0.0) then f
      else if Float.rem f 2.0 = 0.0 then f
      else f +. 1.0
    in
    Float.ldexp n (-1074)

(* sqrt a to double-double: one Newton correction from the residual
   a - hi^2, formed exactly. *)
let sqrt a =
  if a.hi <= 0.0 then of_float (Float.sqrt a.hi)
  else
    let hi = Float.sqrt a.hi in
    let r = sub a (two_prod hi hi) in
    renormalise hi (r.hi /. (2.0 *. hi))
