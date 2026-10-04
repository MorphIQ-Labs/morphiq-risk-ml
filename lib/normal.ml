let inv_sqrt_2 = 0.70710678118654752440
let inv_sqrt_2pi = 0.39894228040143267794

(* [scale * exp(-u^2/2)] for u >= 0, with u^2 split exactly so the
   half-square carries no rounding into the exponential. *)
let scaled_gaussian scale u =
  let hi, lo = Split.square u in
  Split.scaled_exp_neg scale (0.5 *. hi) (0.5 *. lo)

let norm_pdf x =
  if Float.is_nan x then x else scaled_gaussian inv_sqrt_2pi (Float.abs x)

(* |x| at or below which the generated small-erf interval applies to x / sqrt 2. *)
let erf_region = Cody.thresh /. inv_sqrt_2

(* Q(u) = 1 - Phi(u) for u above the erf region. *)
let upper_tail u =
  scaled_gaussian (0.5 *. Cody.erfcx_nonnegative (u *. inv_sqrt_2)) u

let norm_cdf x =
  if Float.is_nan x then x
  else
    let u = Float.abs x in
    if u <= erf_region then 0.5 +. (0.5 *. Cody.erf_small (x *. inv_sqrt_2))
    else
      let q = upper_tail u in
      if x < 0.0 then q else 1.0 -. q

let log_norm_cdf x =
  if Float.is_nan x then x
  else if x = Float.neg_infinity then Float.neg_infinity
  else
    let u = Float.abs x in
    if u <= erf_region then Elementary.log (norm_cdf x)
    else if x > 0.0 then Elementary.log1p (-.upper_tail u)
    else
      (* The half-square is formed directly, h + l = u^2/2 exactly, so it
         stays finite wherever ln Phi is (x^2 itself overflows first). *)
      let half_u = 0.5 *. u in
      let h = half_u *. u in
      if h = Float.infinity then Float.neg_infinity
      else
        let l = Float.fma half_u u (-.h) in
        Elementary.log (0.5 *. Cody.erfcx_nonnegative (u *. inv_sqrt_2))
        -. h -. l

(* Project-derived safeguarded inversion of the Gaussian integral.
   No AS241 table or reduction survives. See docs/inverse-normal-replacement.md. *)
let inverse_steps = 6
let twice_inv_sqrt_pi = 2.0 *. Erf_coefficients.inv_sqrt_pi

let inverse_central t =
  let rec solve remaining lower upper y =
    if remaining = 0 then y
    else
      let value = Cody.erf_small y in
      let residual = value -. t in
      let uncertainty = Float.next_after (0x1p-48 *. value) Float.infinity in
      let lower, upper =
        if residual > uncertainty then (lower, y)
        else if residual < -.uncertainty then (y, upper)
        else (lower, upper)
      in
      let derivative = twice_inv_sqrt_pi *. Elementary.exp (-.(y *. y)) in
      let proposed = y -. (residual /. derivative) in
      let next = Float.max lower (Float.min upper proposed) in
      solve (remaining - 1) lower upper next
  in
  solve inverse_steps (0.5 *. t) t t

let inverse_tail probability =
  let target = Dd.neg (Dd.log_float (2.0 *. probability)) in
  let rec solve remaining lower upper y =
    if remaining = 0 then y
    else
      let scaled = Cody.erfcx_nonnegative y in
      let logarithm = Elementary.log scaled in
      let residual = Float.fma y y (-.target.hi) -. target.lo -. logarithm in
      let uncertainty =
        Float.next_after
          (0x1p-46 *. (1.0 +. Float.abs logarithm))
          Float.infinity
      in
      let lower, upper =
        if residual > uncertainty then (lower, y)
        else if residual < -.uncertainty then (y, upper)
        else (lower, upper)
      in
      let proposed = y -. (residual *. (scaled /. twice_inv_sqrt_pi)) in
      let next = Float.max lower (Float.min upper proposed) in
      solve (remaining - 1) lower upper next
  in
  solve inverse_steps 0.0 28.0 (Float.sqrt target.hi)

let norm_inv p =
  if Float.is_nan p || p < 0.0 || p > 1.0 then Float.nan
  else if p = 0.0 then Float.neg_infinity
  else if p = 1.0 then Float.infinity
  else if p = 0.5 then 0.0
  else
    let q = p -. 0.5 in
    let y =
      if Float.abs q <= 0.25 then inverse_central (2.0 *. Float.abs q)
      else inverse_tail (if p < 0.5 then p else 1.0 -. p)
    in
    let x = y /. inv_sqrt_2 in
    let x =
      if x <= Normal_dd.limit then
        let negative = Dd.of_float (-.x) in
        let probability = if p < 0.5 then p else 1.0 -. p in
        let residual =
          Dd.sub (Normal_dd.cdf negative) (Dd.of_float probability)
        in
        -.Dd.to_float
            (Dd.sub negative (Dd.div residual (Normal_dd.pdf negative)))
      else x
    in
    if p < 0.5 then -.x else x

(* Phi(hi + lo) for |lo| <= ulp(hi), to first order in lo. Phi(hi) is exact
   in its argument, so a double-double argument keeps the tail's relative
   accuracy, which a rounded argument loses at rate |d|. *)
let norm_cdf_dd hi lo =
  if lo = 0.0 then norm_cdf hi else norm_cdf hi +. (norm_pdf hi *. lo)
