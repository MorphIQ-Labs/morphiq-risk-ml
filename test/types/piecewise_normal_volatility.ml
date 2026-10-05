open Morphiq_risk
module P = Early_exercise.Bsm.Piecewise

let curve (initial : Vol.normal Vol.t) =
  P.Volatility.create ~horizon:1. ~initial ~changes:[||]
