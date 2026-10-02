open Morphiq_risk

let annual (v : (Units.per_year, Vol.lognormal) Units.volatility_time_rate) = v
let invalid (g : Vol.lognormal Greeks.t) = annual (Result.get_ok g.veta)
