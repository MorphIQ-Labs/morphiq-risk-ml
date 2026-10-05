open Morphiq_risk

let certify (p : Early_exercise.Bsm.estimated_price) :
    float Production.certified =
  p
