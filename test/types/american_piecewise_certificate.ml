open Morphiq_risk
module A = Early_exercise.Bsm

let certify (p : A.Piecewise.admitted) limit =
  A.Certified.price p Side.Call ~max_error:limit
