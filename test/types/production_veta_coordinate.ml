open Morphiq_risk

let wrong (a : Production.Bsm.admitted)
    (limit : (Units.per_calendar_day, Vol.normal) Units.volatility_time_rate) =
  Production.Bsm.evaluate a Side.Call
    (Result.get_ok (Vol.lognormal 0.2))
    Production.Veta ~max_error:limit
