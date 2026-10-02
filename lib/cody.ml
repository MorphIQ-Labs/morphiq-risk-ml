(* W. J. Cody, "Rational Chebyshev approximations for the error function",
   Math. Comp. 23 (1969) 631-637; netlib specfun CALERF (March 19, 1990).
   Coefficients are the published double-precision values. *)

let thresh = 0.46875
let sqrpi = 5.6418958354775628695e-1 (* 1/sqrt(pi) *)

(* IEEE double-precision machine constants from CALERF. CALERF's XMAX
   (2.53e307), which flushes erfcx to zero, is not used: past it the
   asymptote sqrt(1/pi)/y is a subnormal that one division rounds correctly. *)
let xneg = -26.628
let xsmall = 1.11e-16
let xbig = 26.543
let xhuge = 6.71e7

let a0 = 3.16112374387056560e00
let a1 = 1.13864154151050156e02
let a2 = 3.77485237685302021e02
let a3 = 3.20937758913846947e03
let a4 = 1.85777706184603153e-1
let b0 = 2.36012909523441209e01
let b1 = 2.44024637934444173e02
let b2 = 1.28261652607737228e03
let b3 = 2.84423683343917062e03

let c0 = 5.64188496988670089e-1
let c1 = 8.88314979438837594e0
let c2 = 6.61191906371416295e01
let c3 = 2.98635138197400131e02
let c4 = 8.81952221241769090e02
let c5 = 1.71204761263407058e03
let c6 = 2.05107837782607147e03
let c7 = 1.23033935479799725e03
let c8 = 2.15311535474403846e-8
let d0 = 1.57449261107098347e01
let d1 = 1.17693950891312499e02
let d2 = 5.37181101862009858e02
let d3 = 1.62138957456669019e03
let d4 = 3.29079923573345963e03
let d5 = 4.36261909014324716e03
let d6 = 3.43936767414372164e03
let d7 = 1.23033935480374942e03

let p0 = 3.05326634961232344e-1
let p1 = 3.60344899949804439e-1
let p2 = 1.25781726111229246e-1
let p3 = 1.60837851487422766e-2
let p4 = 6.58749161529837803e-4
let p5 = 1.63153871373020978e-2
let q0 = 2.56852019228982242e00
let q1 = 1.87295284992346047e00
let q2 = 5.27905102951428412e-1
let q3 = 6.05183413124413191e-2
let q4 = 2.33520497626869185e-3

(* erf(x) for |x| <= thresh. *)
let erf_small x =
  let y = Float.abs x in
  let ysq = if y > xsmall then y *. y else 0.0 in
  let num = ((((a4 *. ysq) +. a0) *. ysq +. a1) *. ysq +. a2) *. ysq in
  let den = (((ysq +. b0) *. ysq +. b1) *. ysq +. b2) *. ysq in
  x *. (num +. a3) /. (den +. b3)

(* exp(y^2) * erfc(y) for thresh < y <= 4. *)
let erfcx_mid y =
  let num =
    ((((((((c8 *. y) +. c0) *. y +. c1) *. y +. c2) *. y +. c3) *. y +. c4)
      *. y
     +. c5)
     *. y
    +. c6)
    *. y
  in
  let den =
    ((((((((y +. d0) *. y +. d1) *. y +. d2) *. y +. d3) *. y +. d4) *. y +. d5)
      *. y
     +. d6)
    *. y)
  in
  (num +. c7) /. (den +. d7)

(* exp(y^2) * erfc(y) for 4 < y < xhuge. *)
let erfcx_tail y =
  let ysq = 1.0 /. (y *. y) in
  let num = ((((p5 *. ysq) +. p0) *. ysq +. p1) *. ysq +. p2) *. ysq +. p3 in
  let den = ((((ysq +. q0) *. ysq +. q1) *. ysq +. q2) *. ysq +. q3) *. ysq in
  let r = ysq *. ((num *. ysq) +. p4) /. (den +. q4) in
  (sqrpi -. r) /. y

(* exp(-y^2) with the argument split at a multiple of 1/16, so the leading
   square is exact (Cody's device). *)
let exp_neg_square y =
  let ysq = Float.trunc (y *. 16.0) /. 16.0 in
  let del = (y -. ysq) *. (y +. ysq) in
  Float.exp (-.ysq *. ysq) *. Float.exp (-.del)

let exp_square y =
  let ysq = Float.trunc (y *. 16.0) /. 16.0 in
  let del = (y -. ysq) *. (y +. ysq) in
  Float.exp (ysq *. ysq) *. Float.exp del

(* exp(y^2) * erfc(y) for y >= 0. *)
let erfcx_nonnegative y =
  if y <= thresh then Float.exp (y *. y) *. (1.0 -. erf_small y)
  else if y <= 4.0 then erfcx_mid y
  else if y >= xhuge then sqrpi /. y
  else erfcx_tail y

let erfcx x =
  if Float.is_nan x then x
  else if x >= 0.0 then erfcx_nonnegative x
  else if x < xneg then Float.infinity
  else
    let e = exp_square x in
    e +. e -. erfcx_nonnegative (-.x)

let erf x =
  if Float.is_nan x then x
  else
    let y = Float.abs x in
    if y <= thresh then erf_small x
    else
      let erfc_y = if y >= xbig then 0.0 else exp_neg_square y *. erfcx_nonnegative y in
      let r = 0.5 -. erfc_y +. 0.5 in
      if x < 0.0 then -.r else r

let erfc x =
  if Float.is_nan x then x
  else
    let y = Float.abs x in
    if y <= thresh then 1.0 -. erf_small x
    else
      let r = if y >= xbig then 0.0 else exp_neg_square y *. erfcx_nonnegative y in
      if x < 0.0 then 2.0 -. r else r
