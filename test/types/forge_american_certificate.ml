open Morphiq_risk
module C = Early_exercise.Bsm.Certified

let (_ : C.price) = { value = 1.; absolute_error = 0.; reduction = C.Expiry }
