(* Error bounds derived from the library's code paths (docs/error-analysis.md),
   shared by the scorers. They compose the proved double-word primitive bounds
   (§0) with the component bounds test/dd_reference.ml enforces for exp,
   expm1 and log. Magnitudes are evaluated in binary64; they need only a few
   correct digits. *)
let u = 0x1p-53
let u2 = u *. u

(* Analytical majorants, including higher-order slack; see error-analysis §1.
   They apply before final component scaling. Subnormal results additionally
   need an absolute quantum allowance. *)
let eps_exp z =
  (Component_bounds.exp_base +. (Component_bounds.exp_slope *. Float.abs z))
  *. u2

let eps_expm1 z =
  if Float.abs z <= 0.34657359027997264 then
    Component_bounds.expm1_reduced *. u2
  else
    let amplification =
      if z > 0.0 then 1.0 /. -.Float.expm1 (-.z) else 1.0 /. Float.expm1 (-.z)
    in
    (eps_exp z *. amplification) +. (4.0 *. u2)

let eps_log = Component_bounds.log *. u2
let log1p_tail = Component_bounds.log1p_tail
let elementary_exp_relative = Component_bounds.elementary_exp *. u
let erfcx_relative = Component_bounds.erfcx *. u
let y_prime_relative = Component_bounds.y_prime *. u
let normal_pdf_relative = Component_bounds.normal_pdf *. u2
let normal_cdf_absolute = Component_bounds.normal_cdf *. u2

let within ~error ~bound =
  Float.is_finite error && Float.is_finite bound && error >= 0.0 && bound >= 0.0
  && error <= bound

(* Sum a short expansion without losing cancellation between the high and
   low words. This independent TwoSum implementation uses only IEEE additions
   and subtractions, never the library's DD primitives. Each grow step is
   exact; summing the resulting nonoverlapping components costs O(n*u)
   relative to their total, covered by the scorer's explicit inflation. *)
let expansion_error terms =
  if not (List.for_all Float.is_finite terms) then Float.infinity
  else
    let two_sum a b =
      let s = a +. b in
      let bb = s -. a in
      (s, a -. (s -. bb) +. (b -. bb))
    in
    let grow expansion value =
      let q, lows =
        List.fold_left
          (fun (q, lows) component ->
            let sum, error = two_sum q component in
            (sum, if error = 0.0 then lows else error :: lows))
          (value, []) expansion
      in
      List.rev (q :: lows)
    in
    Float.abs (List.fold_left ( +. ) 0.0 (List.fold_left grow [] terms))

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
  let quotient = s' /. k' in
  let ln_ratio, log_terms =
    if Float.is_finite quotient && quotient >= Float.min_float then
      let log_q = Float.log quotient in
      let residual = Float.fma (-.quotient) k' s' /. s' in
      (log_q +. residual, Float.abs log_q)
    else
      ( Float.log s' -. Float.log k',
        Float.abs (Float.log s') +. Float.abs (Float.log k') )
  in
  let l = Float.abs ln_ratio and cy = Float.abs ((r -. q') *. t) in
  let x = ln_ratio +. ((r -. q') *. t) in
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
    (a *. e_x) +. (i *. (eps_expm1 x +. eps_exp (r *. t) +. (10.0 *. u2)))
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
  let reconstruction = 16.0 *. u *. (1.0 +. l +. cy) in
  let near a b = Float.abs (a -. b) <= reconstruction in
  if near (Float.abs x) 0.35 || near (l +. cy) 1.0 then
    Float.max via_expm1 via_legs
  else if Float.abs x <= 0.35 && l +. cy <= 1.0 then via_expm1
  else via_legs

(* Enforced ULP budgets: the measured worst case per region with roughly 2x
   headroom, so a regression to FerroRisk-level error fails. The ε·scale
   budget stays FerroRisk's. Measured worst: deep ITM 3, ITM 7, near-ATM 4,
   OTM 16, extreme scale 10, zero variance 1; Bachelier 3. *)
let price_ulp_budget family region =
  match (family, region) with
  | "black", ("deep_itm" | "near_atm_tiny_variance") -> 8.0
  | "black", "zero_variance" -> 4.0
  | "black", "itm" -> 16.0
  | "black", ("otm" | "extreme_scale") -> 32.0
  | "bachelier", _ -> 8.0
  | _ -> invalid_arg region

(* The largest price budget of a family, for a quantity composed from the
   price whose region is not known. *)
let price_ulp_budget_max = function "bachelier" -> 8.0 | _ -> 32.0

(* Translate the price budget into absolute error before multiplication by T.
   A possible reference lies within budget+1 spacings of the served price;
   take the largest spacing in that enclosure, including a binade crossing. *)
let scaled_price_error ~time ~price ~got ~reference ~budget =
  let radius = (budget +. 1.0) *. ulp price in
  let spacing = ulp (Float.abs price +. radius) in
  let price_error = (budget +. 0.5) *. spacing in
  (Float.abs time *. price_error) +. (0.5 *. ulp got) +. (0.5 *. ulp reference)
