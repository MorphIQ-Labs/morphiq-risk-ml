(* Historical module name retained for Internal consumers. The implementation
   is project-derived from Gaussian integrals; no CALERF coefficients or
   machine constants remain. See docs/error-function-replacement.md and
   oracle/erf_coefficients.py for construction and rational certificates. *)

let thresh = 0.5

let horner coefficients x =
  let result = ref coefficients.(Array.length coefficients - 1) in
  for i = Array.length coefficients - 2 downto 0 do
    result := Float.fma !result x coefficients.(i)
  done;
  !result

(* Integrate the Taylor series of exp(-t²), preserving the leading x. *)
let erf_small x = x *. horner Erf_coefficients.small (x *. x)

let erfcx_nonnegative x =
  if x = 0.0 then 1.0
  else if x >= 0x1p27 then Erf_coefficients.inv_sqrt_pi /. x
  else if x >= 12.0 then
    let inverse = 1.0 /. x in
    Erf_coefficients.inv_sqrt_pi
    *. horner Erf_coefficients.tail (inverse *. inverse)
    /. x
  else
    let index = int_of_float (x *. 4.0) in
    let center = (float index +. 0.5) *. 0.25 in
    let offset = x -. center in
    let coefficients = Erf_coefficients.local.(index) in
    let tail = ref coefficients.(Array.length coefficients - 1) in
    for i = Array.length coefficients - 2 downto 1 do
      tail := Float.fma !tail offset coefficients.(i)
    done;
    coefficients.(0)
    +. Float.fma !tail offset Erf_coefficients.local_low.(index)

let erfcx x =
  if Float.is_nan x then x
  else if x >= 0.0 then erfcx_nonnegative x
  else if x <= -27.0 then Float.infinity
  else
    let hi, lo = Split.square x in
    let ex = Dd.to_float (Dd.exp { hi; lo }) in
    Float.ldexp ex 1 -. erfcx_nonnegative (-.x)

(* 28² > 1075 ln(2): the positive tail rounds to zero beyond this cut.
   Scaling the prefactor with the split square preserves subnormal results. *)
let erfc_positive x =
  if x >= 28.0 then 0.0
  else
    let hi, lo = Split.square x in
    Split.scaled_exp_neg (erfcx_nonnegative x) hi lo

let erf x =
  if Float.is_nan x then x
  else
    let y = Float.abs x in
    if y <= thresh then erf_small x
    else
      let value = 1.0 -. erfc_positive y in
      if x < 0.0 then -.value else value

let erfc x =
  if Float.is_nan x then x
  else
    let y = Float.abs x in
    if y <= thresh then 1.0 -. erf_small x
    else
      let value = erfc_positive y in
      if x < 0.0 then 2.0 -. value else value
