(* Error bounds derived from the library's code paths (docs/error-analysis.md),
   shared by the scorers. They compose the proved double-word primitive bounds
   (§0) with the component bounds test/dd_reference.ml enforces for exp,
   expm1 and log. Magnitudes are evaluated in binary64; they need only a few
   correct digits. *)
let u = 0x1p-53
let u2 = u *. u
let eps_exp z = 0x1p-100 +. (Float.abs z *. 0x1p-105)
let eps_log = 0x1p-100

(* ulp(v), with the subnormal quantum below the normal range. *)
let ulp v =
  let a = Float.abs v in
  if a < Float.min_float then 0x1p-1074
  else Float.ldexp 1.0 (snd (Float.frexp a) - 53)

(* E: the absolute error of the double-word discounted intrinsic I = A - C
   (§5.1). [reference] is |I| when known, else 0 (then |A - C| stands in). *)
let intrinsic_error model ~s ~k ~t ~r ~q ~shift ~reference =
  (* The model's coordinates: displaced Black carries F + d and K + d as
     exact sums, whose low parts enter x to first order. *)
  let s', k', low =
    match model with
    | "displaced" -> (s +. shift, k +. shift, 5.0 *. u2)
    | "black76_shifted" -> (s +. shift, k +. shift, 0.0)
    | _ -> (s, k, 0.0)
  in
  let q' = if model = "bsm" then q else r in
  let ln_q = Float.log s' -. Float.log k' in
  let quotient = s' /. k' in
  let log_terms =
    if Float.is_finite quotient && quotient >= Float.min_float then
      Float.abs ln_q
    else Float.abs (Float.log s') +. Float.abs (Float.log k')
  in
  let l = Float.abs ln_q and cy = Float.abs ((r -. q') *. t) in
  let x = ln_q +. ((r -. q') *. t) in
  let a = s' *. Float.exp (-.q' *. t) and c = k' *. Float.exp (-.r *. t) in
  let i = if reference = 0.0 then Float.abs (a -. c) else Float.abs reference in
  (* x = ln q + (ρ - ρ²/2) + (r - q)T + low parts: ln q to ε_log; ρ by
     Algorithms 18 and 9 (|ρ| <= u); the subtraction, the carry and the two
     additions by Algorithm 6. *)
  let e_x =
    (eps_log *. log_terms)
    +. (15.0 *. u *. u2)
    +. (9.0 *. u2 *. (l +. cy))
    +. low
  in
  (* C expm1(x): the error in x moves it by C e^x = A; expm1, the leg's exp
     and the product (Algorithm 12) are relative. *)
  let via_expm1 =
    (a *. e_x) +. (i *. (eps_exp x +. eps_exp (r *. t) +. (10.0 *. u2)))
  in
  (* A - C: each leg is exp times the coordinate (Algorithm 12), then
     Algorithm 6. *)
  let via_legs =
    (a *. (eps_exp (q' *. t) +. (5.0 *. u2)))
    +. (c *. (eps_exp (r *. t) +. (5.0 *. u2)))
    +. (3.0 *. u2 *. i)
  in
  (* The code's branch: |x| <= 0.35 and x's terms <= 1. Within a hair of
     either threshold the binary64 magnitudes cannot tell which branch ran. *)
  let near a b = Float.abs (a -. b) <= 1e-9 *. b in
  if near (Float.abs x) 0.35 || near (l +. cy) 1.0 then
    Float.max via_expm1 via_legs
  else if Float.abs x <= 0.35 && l +. cy <= 1.0 then via_expm1
  else via_legs
