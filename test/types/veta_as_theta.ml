open Morphiq_risk

let theta (v : Units.per_calendar_day Units.time_rate) = v
let invalid (g : Vol.lognormal Greeks.t) = theta (Result.get_ok g.veta)
