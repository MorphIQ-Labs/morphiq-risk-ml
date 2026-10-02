let inv_sqrt_2 = 0.70710678118654752440
let inv_sqrt_2pi = 0.39894228040143267794

(* [scale * exp(-u^2/2)] for u >= 0, with u^2 split exactly so the
   half-square carries no rounding into the exponential. *)
let scaled_gaussian scale u =
  let hi, lo = Split.square u in
  Split.scaled_exp_neg scale (0.5 *. hi) (0.5 *. lo)

let norm_pdf x =
  if Float.is_nan x then x else scaled_gaussian inv_sqrt_2pi (Float.abs x)

(* |x| at or below which Cody's erf interval applies to x / sqrt 2. *)
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
    if u <= erf_region then Float.log (norm_cdf x)
    else if x > 0.0 then Float.log1p (-.upper_tail u)
    else
      (* The half-square is formed directly, h + l = u^2/2 exactly, so it
         stays finite wherever ln Phi is (x^2 itself overflows first). *)
      let half_u = 0.5 *. u in
      let h = half_u *. u in
      if h = Float.infinity then Float.neg_infinity
      else
        let l = Float.fma half_u u (-.h) in
        Float.log (0.5 *. Cody.erfcx_nonnegative (u *. inv_sqrt_2)) -. h -. l

(* M. J. Wichura, Algorithm AS 241 (PPND16), Appl. Statist. 37 (1988) 477-484. *)
module As241 = struct
  let split1 = 0.425
  let split2 = 5.0
  let const1 = 0.180625
  let const2 = 1.6

  let central q =
    let r = const1 -. (q *. q) in
    q
    *. (((((((2.5090809287301226727e3 *. r +. 3.3430575583588128105e4) *. r
            +. 6.7265770927008700853e4)
            *. r
           +. 4.5921953931549871457e4)
           *. r
          +. 1.3731693765509461125e4)
          *. r
         +. 1.9715909503065514427e3)
         *. r
        +. 1.3314166789178437745e2)
        *. r
       +. 3.3871328727963666080e0)
    /. (((((((5.2264952788528545610e3 *. r +. 2.8729085735721942674e4) *. r
            +. 3.9307895800092710610e4)
            *. r
           +. 2.1213794301586595867e4)
           *. r
          +. 5.3941960214247511077e3)
          *. r
         +. 6.8718700749205790830e2)
         *. r
        +. 4.2313330701600911252e1)
        *. r
       +. 1.0)

  let intermediate r =
    let r = r -. const2 in
    (((((((7.74545014278341407640e-4 *. r +. 2.27238449892691845833e-2) *. r
          +. 2.41780725177450611770e-1)
          *. r
         +. 1.27045825245236838258e0)
         *. r
        +. 3.64784832476320460504e0)
        *. r
       +. 5.76949722146069140550e0)
       *. r
      +. 4.63033784615654529590e0)
      *. r
     +. 1.42343711074968357734e0)
    /. (((((((1.05075007164441684324e-9 *. r +. 5.47593808499534494600e-4)
              *. r
             +. 1.51986665636164571966e-2)
             *. r
            +. 1.48103976427480074590e-1)
            *. r
           +. 6.89767334985100004550e-1)
           *. r
          +. 1.67638483018380384940e0)
          *. r
         +. 2.05319162663775882187e0)
         *. r
        +. 1.0)

  let far r =
    let r = r -. split2 in
    (((((((2.01033439929228813265e-7 *. r +. 2.71155556874348757815e-5) *. r
          +. 1.24266094738807843860e-3)
          *. r
         +. 2.65321895265761230930e-2)
         *. r
        +. 2.96560571828504891230e-1)
        *. r
       +. 1.78482653991729133580e0)
       *. r
      +. 5.46378491116411436990e0)
      *. r
     +. 6.65790464350110377720e0)
    /. (((((((2.04426310338993978564e-15 *. r +. 1.42151175831644588870e-7)
              *. r
             +. 1.84631831751005468180e-5)
             *. r
            +. 7.86869131145613259100e-4)
            *. r
           +. 1.48753612908506148525e-2)
           *. r
          +. 1.36929880922735805310e-1)
          *. r
         +. 5.99832206555887937690e-1)
         *. r
        +. 1.0)
end

let norm_inv p =
  if Float.is_nan p || p < 0.0 || p > 1.0 then Float.nan
  else if p = 0.0 then Float.neg_infinity
  else if p = 1.0 then Float.infinity
  else
    let q = p -. 0.5 in
    if Float.abs q <= As241.split1 then As241.central q
    else
      let r = Float.sqrt (-.Float.log (if q < 0.0 then p else 1.0 -. p)) in
      let z = if r <= As241.split2 then As241.intermediate r else As241.far r in
      if q < 0.0 then -.z else z
