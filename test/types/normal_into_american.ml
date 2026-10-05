open Morphiq_risk

let mix (p : Early_exercise.Bsm.inputs) (v : Vol.normal Vol.t) =
  { p with volatility = v }
