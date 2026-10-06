open Morphiq_risk

let forge (x : Early_exercise.Bsm.Implied_volatility.estimated_interval) =
  { x with requested_width = 0. }
