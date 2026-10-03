open Morphiq_risk

let wrong (a : Production.Bsm.admitted) (limit : Units.per_year Units.time_rate)
    =
  Production.Bsm.evaluate a Side.Call
    (Result.get_ok (Vol.lognormal 0.2))
    Production.Theta ~max_error:limit
