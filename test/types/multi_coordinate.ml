open Morphiq_risk

let normal : Vol.normal Production.request =
  Production.Request (Production.Vega, Units.per_volatility 1e-8)

let lognormal : Vol.lognormal Production.request list = [ normal ]
