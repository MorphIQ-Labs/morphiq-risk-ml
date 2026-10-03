open Morphiq_risk

let wrong (a : Production.Bsm.admitted) =
  Production.Black76.evaluate a Side.Call
    (Result.get_ok (Vol.lognormal 0.2))
    Production.Price ~max_error:1e-10
