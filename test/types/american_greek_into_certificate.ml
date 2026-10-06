open Morphiq_risk

let certify (p : Early_exercise.Bsm.estimated_greek) :
    float Production.certified =
  p
