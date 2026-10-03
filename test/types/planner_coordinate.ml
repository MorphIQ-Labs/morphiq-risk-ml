open Morphiq_risk

let normal : Vol.normal Planner.output =
  Planner.Output (Production.Vega, Units.per_volatility 1e-10)

let lognormal : Vol.lognormal Planner.output = normal
