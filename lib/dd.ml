(* Double-double ("double-word") arithmetic: a value is the unevaluated sum
   hi + lo with hi = RN(hi + lo) (Dekker 1971).

   The primitives are the algorithms of Joldes, Muller and Popescu, "Tight and
   rigorous error bounds for basic building blocks of double-word arithmetic",
   ACM TOMS 44(2), 2017 (JMP), and the square root of Lefèvre, Louvet,
   Muller, Picot and Rideau, "Accurate calculation of Euclidean norms using
   double-word arithmetic", ACM TOMS 49(1), 2023 (LLMPR), each with its proved
   relative error bound, u = 2^-53. The bounds assume no underflow or
   overflow. *)

type t = { hi : float; lo : float }

let of_float hi = { hi; lo = 0.0 }

(* Fast2Sum (Dekker 1971; JMP Algorithm 1): exact when hi's exponent is at
   least lo's. *)
let renormalise hi lo =
  let s = hi +. lo in
  { hi = s; lo = lo -. (s -. hi) }

(* AccurateDWPlusDW, JMP Algorithm 6: relative error <= 3u^2 + 13u^3. *)
let add a b =
  let s, e = Split.two_sum a.hi b.hi in
  let t, f = Split.two_sum a.lo b.lo in
  let { hi; lo } = renormalise s (e +. t) in
  renormalise hi (lo +. f)

let neg a = { hi = -.a.hi; lo = -.a.lo }
let sub a b = add a (neg b)

(* 2Prod by fma (Fast2Mult, JMP Algorithm 3): exact. *)
let two_prod a b =
  let p = a *. b in
  { hi = p; lo = Float.fma a b (-.p) }

(* DWPlusFP, JMP Algorithm 4: relative error <= 2u^2. *)
let add_float a y =
  let s, e = Split.two_sum a.hi y in
  renormalise s (a.lo +. e)

(* DWTimesFP3, JMP Algorithm 9: relative error <= 2u^2. *)
let mul_float a y =
  let p = two_prod a.hi y in
  renormalise p.hi (Float.fma a.lo y p.lo)

(* DWTimesDW3, JMP Algorithm 12: relative error <= 5u^2. *)
let mul a b =
  let p = two_prod a.hi b.hi in
  let t0 = a.lo *. b.lo in
  let t1 = Float.fma a.hi b.lo t0 in
  let c2 = Float.fma a.lo b.hi t1 in
  renormalise p.hi (p.lo +. c2)

let scale a k =
  let hi = Float.ldexp a.hi k and lo = Float.ldexp a.lo k in
  (* Rounding a low word onto the subnormal grid can create a halfway
     overlap with an odd high significand. Restore the DD invariant before
     the pair is consumed by another primitive. Fast2Sum preserves its sum. *)
  if lo <> 0.0 && Float.abs lo < Float.min_float && Float.is_finite hi then
    renormalise hi lo
  else { hi; lo }

(* DWDivDW3, JMP Algorithm 18: one Newton step for 1/b, then a product;
   relative error <= 9.8u^2. The bound assumes an unbounded exponent range,
   so the divisor and any extreme dividend are normalised before the
   reciprocal and product. A dividend in [2^-400,2^400] already leaves ample
   exponent room for the reciprocal product and its residual.
   Normalising only b lets the product underflow before a normal quotient
   is restored. Final component scaling can lose a subnormal low word;
   the finite-exponent bound includes that absolute rounding error. *)
let div a b =
  if b.hi = 0.0 || not (Float.is_finite b.hi) then of_float (a.hi /. b.hi)
  else
    let ka =
      if Float.abs a.hi >= 0x1p-400 && Float.abs a.hi <= 0x1p400 then 0
      else snd (Float.frexp a.hi) - 1
    in
    let kb = snd (Float.frexp b.hi) - 1 in
    let a = if ka = 0 then a else scale a (-ka) in
    let b = scale b (-kb) in
    let th = 1.0 /. b.hi in
    let rh = Float.fma (-.b.hi) th 1.0 in
    let rl = -.(b.lo *. th) in
    let e = renormalise rh rl in
    let d = mul_float e th in
    let m = add_float d th in
    scale (mul a m) (ka - kb)

let to_float a = a.hi +. a.lo

(* ln 2 = ln2_hi + ln2_lo to 106 bits. *)
let ln2 = { hi = 0x1.62e42fefa39efp-1; lo = 0x1.abc9e3b39803fp-56 }
let compare_float a f = if a.hi <> f then compare a.hi f else compare a.lo 0.0

(* exp and expm1 adapt the QD library's dd_real (Hida, Li and Bailey,
   qd-2.3.24, dd_real.cpp), with its reduction constant k = 512 and its
   stopping rule. Copyright (c) 2003-2023, The Regents of the University of
   California through Lawrence Berkeley National Laboratory; see the original
   COPYING and BSD-LBNL-License documents in LICENSES/ and the scope review in
   docs/source-provenance.md.
   One departure: exp covers the binary64 range down to the
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
  (* Below this threshold |expm1(x)-x|/|x| < 2^-105. In particular,
     dividing a subnormal x by 512 would destroy significant bits. *)
  if Float.abs x.hi < 0x1p-104 then x
  else if Float.abs x.hi <= 0.34657359027997264 then
    expm1_reduced (scale x (-9))
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

(* SQRTDWtoDW, LLMPR Algorithm 8: relative error <= 25/8 u^2. *)
let sqrt a =
  if a.hi <= 0.0 then of_float (Float.sqrt a.hi)
  else
    let k =
      if a.hi >= 0x1p-400 && a.hi <= 0x1p400 then 0
      else (snd (Float.frexp a.hi) - 1) asr 1
    in
    let a = if k = 0 then a else scale a (-2 * k) in
    let sh = Float.sqrt a.hi in
    let rho1 = Float.fma (-.sh) sh a.hi in
    let rho2 = a.lo +. rho1 in
    let result = renormalise sh (rho2 /. (2.0 *. sh)) in
    if k = 0 then result else scale result k
