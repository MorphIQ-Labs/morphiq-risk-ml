open Morphiq_risk
module A = Early_exercise.Bsm

let price cfg (p : A.Piecewise.admitted) = A.price cfg p Side.Put
