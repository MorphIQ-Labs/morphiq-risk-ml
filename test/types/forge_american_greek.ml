open Morphiq_risk

let forge (p : Early_exercise.Bsm.estimated_greek) = { p with value = 1. }
