open Morphiq_risk

let wrong cfg (x : Early_exercise.Bsm.Piecewise.admitted) quote =
  Early_exercise.Bsm.Implied_volatility.solve cfg x Side.Call quote
