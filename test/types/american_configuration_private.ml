open Morphiq_risk

let invalid (cfg : Early_exercise.Bsm.configuration) =
  { cfg with tolerance = nan }
