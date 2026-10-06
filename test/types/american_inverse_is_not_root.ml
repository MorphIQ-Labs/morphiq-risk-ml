open Morphiq_risk

let cast (x : Early_exercise.Bsm.Implied_volatility.estimated_interval) :
    Vol.lognormal Iv.t =
  x
