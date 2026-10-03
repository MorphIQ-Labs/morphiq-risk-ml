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
   least lo's. Inlining lets callers eliminate temporary pairs while retaining
   each explicitly rounded operation. *)
let renormalise hi lo =
  let s = hi +. lo in
  { hi = s; lo = lo -. (s -. hi) }
[@@inline always]

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
[@@inline always]

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

(* Project derivation from exp(x) = sum x^n/n!: direct degree-22 Horner
   evaluation on |r| < .347, with exact-rational generated coefficient splits.
   See oracle/dd_exp_coefficients.py and docs/error-analysis.md, section 1.2.
   This replaces the historical QD adaptation; no QD table or stopping rule
   is used here. *)

let exp_coefficients =
  [|
    { hi = 0x1.0000000000000p+0; lo = 0x0.0p+0 };
    { hi = 0x1.0000000000000p-1; lo = 0x0.0p+0 };
    { hi = 0x1.5555555555555p-3; lo = 0x1.5555555555555p-57 };
    { hi = 0x1.5555555555555p-5; lo = 0x1.5555555555555p-59 };
    { hi = 0x1.1111111111111p-7; lo = 0x1.1111111111111p-63 };
    { hi = 0x1.6c16c16c16c17p-10; lo = -0x1.f49f49f49f49fp-65 };
    { hi = 0x1.a01a01a01a01ap-13; lo = 0x1.a01a01a01a01ap-73 };
    { hi = 0x1.a01a01a01a01ap-16; lo = 0x1.a01a01a01a01ap-76 };
    { hi = 0x1.71de3a556c734p-19; lo = -0x1.c154f8ddc6c00p-73 };
    { hi = 0x1.27e4fb7789f5cp-22; lo = 0x1.cbbc05b4fa99ap-76 };
    { hi = 0x1.ae64567f544e4p-26; lo = -0x1.c062e06d1f209p-80 };
    { hi = 0x1.1eed8eff8d898p-29; lo = -0x1.2aec959e14c06p-83 };
    { hi = 0x1.6124613a86d09p-33; lo = 0x1.f28e0cc748ebep-87 };
    { hi = 0x1.93974a8c07c9dp-37; lo = 0x1.05d6f8a2efd1fp-92 };
    { hi = 0x1.ae7f3e733b81fp-41; lo = 0x1.1d8656b0ee8cbp-97 };
    { hi = 0x1.ae7f3e733b81fp-45; lo = 0x1.1d8656b0ee8cbp-101 };
    { hi = 0x1.952c77030ad4ap-49; lo = 0x1.ac981465ddc6cp-103 };
    { hi = 0x1.6827863b97d97p-53; lo = 0x1.eec01221a8b0bp-107 };
    { hi = 0x1.2f49b46814157p-57; lo = 0x1.2650f61dbdcb4p-112 };
    { hi = 0x1.e542ba4020225p-62; lo = 0x1.ea72b4afe3c2fp-120 };
    { hi = 0x1.71b8ef6dcf572p-66; lo = -0x1.d043ae40c4647p-120 };
    { hi = 0x1.0ce396db7f853p-70; lo = -0x1.aebcdbd20331cp-124 };
  |]

(* r + r²*(1/2 + r*(1/3! + ...)): preserve the exact leading r rather
   than rounding 1 plus the correction before multiplying by r. The tail
   uses DD Horner, with an exact binary64 coefficient at its final step. *)
let expm1_reduced r =
  (* Below this threshold the omitted relative tail is below 2u²; bypassing
     Horner also avoids subnormal leading products in both exp and expm1. *)
  if Float.abs r.hi < 0x1p-104 then r
  else
    let acc = ref exp_coefficients.(21) in
    for k = 20 downto 2 do
      acc :=
        (add [@inlined always]) exp_coefficients.(k)
          ((mul [@inlined always]) r !acc)
    done;
    let acc =
      (add_float [@inlined always]) ((mul [@inlined always]) r !acc) 0.5
    in
    (add [@inlined always]) r
      ((mul [@inlined always]) ((mul [@inlined always]) r r) acc)

let exp x =
  if x.hi < -745.2 then of_float 0.0
  else if x.hi > 709.8 then of_float Float.infinity
  else if x.hi = 0.0 then of_float 1.0
  else
    let m = Float.floor ((x.hi /. ln2.hi) +. 0.5) in
    let r = sub x (mul_float ln2 m) in
    scale (add (expm1_reduced r) (of_float 1.0)) (int_of_float m)

(* e^x - 1 directly on the small interval, avoiding cancellation against 1. *)
let expm1 x =
  if Float.abs x.hi <= 0.34657359027997264 then expm1_reduced x
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
