open Morphiq_risk
module P = Early_exercise.Bsm.Piecewise

let confuse (rate : P.Rate.t) : P.Yield.t = rate
