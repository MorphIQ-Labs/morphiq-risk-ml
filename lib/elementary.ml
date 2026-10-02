(* Elementary functions from IEEE-754 basic operations and fma only.

   The platform libm is not used: its results differ between systems
   (macOS, glibc, musl), so a library built on it serves different numbers
   on different machines. These are deterministic: binary64 +, -, *, /,
   sqrt and fma are correctly rounded everywhere, so a fixed sequence of
   them gives the same bits on every conforming platform. Accuracy is about
   1 ULP; see test/oracle_elementary.ml.

   Constructions are the classic ones (Cody & Waite 1980; fdlibm/Tang 1989):
   argument reduction by a two-part ln 2, then a polynomial on the reduced
   interval. *)

(* ln 2 split so that k * ln2_hi is exact for |k| < 2^20 (fdlibm). *)
let ln2_hi = 0x1.62e42feep-1
let ln2_lo = 0x1.a39ef35793c76p-33
let inv_ln2 = 0x1.71547652b82fep0

(* Horner evaluation of c0 + c1 v + c2 v^2 + ... from a coefficient array,
   highest power evaluated first. *)
let horner coefficients v =
  let n = Array.length coefficients in
  let acc = ref coefficients.(n - 1) in
  for i = n - 2 downto 0 do
    acc := coefficients.(i) +. (v *. !acc)
  done;
  !acc

(* 1/(n+1)! for n = 0..13, correctly rounded (checked against mpmath). *)
let exp_coefficients =
  [|
    1.0;
    0.5;
    0x1.5555555555555p-3;
    0x1.5555555555555p-5;
    0x1.1111111111111p-7;
    0x1.6c16c16c16c17p-10;
    0x1.a01a01a01a01ap-13;
    0x1.a01a01a01a01ap-16;
    0x1.71de3a556c734p-19;
    0x1.27e4fb7789f5cp-22;
    0x1.ae64567f544e4p-26;
    0x1.1eed8eff8d898p-29;
    0x1.6124613a86d09p-33;
    0x1.93974a8c07c9dp-37;
  |]

(* e^r - 1 = r Σ r^n/(n+1)! for |r| <= ln 2 / 2 + a little; the degree-14
   truncation is below 2^-60 relative on that interval. *)
let expm1_reduced r = r *. horner exp_coefficients r

(* The same series to degree 21 for |x| <= 1, where 1/22! < 2^-70: expm1 is
   then one Horner evaluation, without recombining across a reduction. *)
let expm1_coefficients =
  [|
    0x1.0000000000000p+0;
    0x1.0000000000000p-1;
    0x1.5555555555555p-3;
    0x1.5555555555555p-5;
    0x1.1111111111111p-7;
    0x1.6c16c16c16c17p-10;
    0x1.a01a01a01a01ap-13;
    0x1.a01a01a01a01ap-16;
    0x1.71de3a556c734p-19;
    0x1.27e4fb7789f5cp-22;
    0x1.ae64567f544e4p-26;
    0x1.1eed8eff8d898p-29;
    0x1.6124613a86d09p-33;
    0x1.93974a8c07c9dp-37;
    0x1.ae7f3e733b81fp-41;
    0x1.ae7f3e733b81fp-45;
    0x1.952c77030ad4ap-49;
    0x1.6827863b97d97p-53;
    0x1.2f49b46814157p-57;
    0x1.e542ba4020225p-62;
    0x1.71b8ef6dcf572p-66;
  |]

let expm1_direct x = x *. horner expm1_coefficients x

(* k = round(x / ln 2), r = x - k ln 2 with k ln2_hi exact. *)
let reduce x =
  let k = Float.round (x *. inv_ln2) in
  let r = Float.fma (-.k) ln2_lo (Float.fma (-.k) ln2_hi x) in
  (k, r)

let exp x =
  if Float.is_nan x then x
  else if x > 709.782712893384 then Float.infinity
  else if x < -745.1332191019412 then 0.0
  else if Float.abs x < 0x1p-54 then 1.0 +. x
  else
    let k, r = reduce x in
    let v = 1.0 +. expm1_reduced r in
    (* 2^k may itself overflow or underflow where v 2^k does not. *)
    let k = int_of_float k in
    if k > 1023 then Float.ldexp (Float.ldexp v 1023) (k - 1023)
    else if k < -1021 then Float.ldexp (Float.ldexp v (-1021)) (k + 1021)
    else Float.ldexp v k

let expm1 x =
  if Float.is_nan x then x
  else if Float.abs x <= 1.0 then expm1_direct x
  else if x < -40.0 then -1.0
  else if x > 709.782712893384 then Float.infinity
  else
    let k, r = reduce x in
    let em1 = expm1_reduced r in
    let k = int_of_float k in
    (* 2^k (1 + em1) - 1, with the subtraction ordered to keep accuracy. *)
    if k <= 60 then Float.ldexp em1 k +. (Float.ldexp 1.0 k -. 1.0)
    else Float.ldexp (1.0 +. em1) k -. 1.0

(* 1/(2k+1) for k = 1..10, correctly rounded (checked against mpmath). *)
let atanh_coefficients =
  [|
    0x1.5555555555555p-2;
    0x1.999999999999ap-3;
    0x1.2492492492492p-3;
    0x1.c71c71c71c71cp-4;
    0x1.745d1745d1746p-4;
    0x1.3b13b13b13b14p-4;
    0x1.1111111111111p-4;
    0x1.e1e1e1e1e1e1ep-5;
    0x1.af286bca1af28p-5;
    0x1.8618618618618p-5;
  |]

(* ln(1 + f) for f in [sqrt(1/2) - 1, sqrt 2 - 1], as 2 atanh(f / (2 + f)):
   u = f/(2+f), |u| <= 0.1716, v = u^2 <= 0.0295, and the series
   Σ v^k/(2k+1) to k = 10 truncates below 2^-60 relative. *)
(* Knuth's TwoSum, local so that Split may depend on this module. *)
let two_sum a b =
  let s = a +. b in
  let bb = s -. a in
  (s, a -. (s -. bb) +. (b -. bb))

let log1p_reduced f =
  (* u = f / (2 + f) with its remainder: 2 + f = d + dl exactly, and
     f - u d is exact by fma, so u + ul is the quotient to about 2^-106. The
     leading 2u then carries no rounding of its own. *)
  let d, dl = two_sum 2.0 f in
  let u = f /. d in
  let ul = (Float.fma (-.u) d f -. (u *. dl)) /. d in
  let v = u *. u in
  (2.0 *. u) +. ((2.0 *. ul) +. (2.0 *. u *. (v *. horner atanh_coefficients v)))

let sqrt_half = 0x1.6a09e667f3bcdp-1

let log x =
  if Float.is_nan x || x < 0.0 then Float.nan
  else if x = 0.0 then Float.neg_infinity
  else if x = Float.infinity then x
  else
    let m, e = Float.frexp x in
    let m, e = if m < sqrt_half then (2.0 *. m, e - 1) else (m, e) in
    let f = m -. 1.0 in
    let e = float e in
    (e *. ln2_hi) +. (log1p_reduced f +. (e *. ln2_lo))

let log1p x =
  if Float.abs x < 0x1p-54 then
    (* x - x^2/2 + ...: x^2/2 < ulp(x)/4, so x is the correctly rounded
       result (fdlibm s_log1p.c); ±0 keeps its sign. Below this the reduced
       path's u = x/2 would underflow and lose x's last bit. *)
    x
  else if Float.is_nan x || x < -1.0 then Float.nan
  else if x = -1.0 then Float.neg_infinity
  else if x = Float.infinity then x
  else if x >= sqrt_half -. 1.0 && x <= 0x1.6a09e667f3bcdp0 -. 1.0 then
    log1p_reduced x
  else
    (* 1 + x rounds; c = (x - (u - 1))/u restores what the rounding dropped. *)
    let u = 1.0 +. x in
    let c = (x -. (u -. 1.0)) /. u in
    log u +. c

(* A cube root for initial guesses: deterministic, about 1 ULP after two
   Newton steps from exp(log|x|/3). *)
let cbrt x =
  if x = 0.0 || Float.is_nan x || Float.abs x = Float.infinity then x
  else
    let a = Float.abs x in
    let y = exp (log a /. 3.0) in
    let y = y -. (((y *. y *. y) -. a) /. (3.0 *. y *. y)) in
    let y = y -. (((y *. y *. y) -. a) /. (3.0 *. y *. y)) in
    Float.copy_sign y x
