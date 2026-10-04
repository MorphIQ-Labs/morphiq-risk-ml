(* The standard normal density and distribution in double-double (~106 bits),
   for |d| <= 6, where a result's relative accuracy is needed below binary64's
   (a cancelling combination of Φ and φ). *)

let inv_sqrt_2pi = { Dd.hi = 0x1.9884533d43651p-2; lo = -0x1.cbc0d30ebfd15p-56 }

(* The domain of {!cdf}: beyond it the series needs too many terms, and the
   binary64 Mills-ratio forms are already relatively accurate. *)
let limit = 6.0

(* φ(d) = e^(-d^2/2) / sqrt(2π), with d^2 formed in DD. *)
let pdf_from_square d2 =
  Dd.mul inv_sqrt_2pi (Dd.exp (Dd.neg (Dd.mul_float d2 0.5)))

let pdf d = pdf_from_square (Dd.mul d d)

(* These are [Dd.div]'s original prepared intermediates, not rounded 1/n
   coefficients. The k>400 cap admits exactly denominators 3 through 801. *)
let series_divisors =
  Array.init 400 (fun i ->
      match Dd.prepare_divisor (Dd.of_float (float ((2 * i) + 3))) with
      | Some divisor -> divisor
      | None -> assert false)

let check_domain d =
  if Float.abs d.Dd.hi > limit then invalid_arg "Normal_dd.cdf: |d| > 6"

(* Phi(d) = 1/2 + phi(d) sum d^(2k+1)/(2k+1)!! (Marsaglia 2004, eq. 2).
   The terms, order and stopping rule are unchanged; prepared division reuses
   only the exact divisor-dependent intermediates of the previous evaluator. *)
let cdf_from_square d d2 density =
  let rec sum k term acc =
    if Float.abs term.Dd.hi <= 0x1p-110 *. Float.abs acc.Dd.hi || k > 400 then
      acc
    else
      let term = Dd.div_prepared (Dd.mul term d2) series_divisors.(k - 1) in
      sum (k + 1) term (Dd.add acc term)
  in
  let series = sum 1 d d in
  Dd.add (Dd.of_float 0.5) (Dd.mul density series)

let cdf d =
  check_domain d;
  let d2 = Dd.mul d d in
  cdf_from_square d d2 (pdf_from_square d2)

let cdf_and_pdf d =
  check_domain d;
  let d2 = Dd.mul d d in
  let density = pdf_from_square d2 in
  (cdf_from_square d d2 density, density)
