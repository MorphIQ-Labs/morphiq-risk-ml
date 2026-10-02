(* The standard normal density and distribution in double-double (~106 bits),
   for |d| <= 6, where a result's relative accuracy is needed below binary64's
   (a cancelling combination of Φ and φ). *)

let inv_sqrt_2pi = { Dd.hi = 0x1.9884533d43651p-2; lo = -0x1.cbc0d30ebfd15p-56 }

(* The domain of {!cdf}: beyond it the series needs too many terms, and the
   binary64 Mills-ratio forms are already relatively accurate. *)
let limit = 6.0

(* φ(d) = e^(-d^2/2) / sqrt(2π), with d^2 formed exactly. *)
let pdf d =
  Dd.mul inv_sqrt_2pi (Dd.exp (Dd.neg (Dd.mul_float (Dd.mul d d) 0.5)))

(* Φ(d) = 1/2 + φ(d) Σ_{k>=0} d^(2k+1) / (2k+1)!!   (Marsaglia 2004, eq. 2).
   Every term has the sign of d, so the sum does not cancel; for d < 0 the
   final 1/2 + negative loses at most log2(1/(2Φ(-6))) ≈ 28 of 106 bits. *)
let cdf d =
  if Float.abs d.Dd.hi > limit then invalid_arg "Normal_dd.cdf: |d| > 6"
  else
    let d2 = Dd.mul d d in
    let rec sum k term acc =
      if Float.abs term.Dd.hi <= 0x1p-110 *. Float.abs acc.Dd.hi || k > 400 then
        acc
      else
        let term =
          Dd.div (Dd.mul term d2) (Dd.of_float (float ((2 * k) + 1)))
        in
        sum (k + 1) term (Dd.add acc term)
    in
    let series = sum 1 d d in
    Dd.add (Dd.of_float 0.5) (Dd.mul (pdf d) series)
