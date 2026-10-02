open Morphiq_risk

let normal_veta
    (v : (Units.per_calendar_day, Vol.normal) Units.volatility_time_rate) =
  v

let invalid (g : Vol.lognormal Greeks.t) = normal_veta (Result.get_ok g.veta)
