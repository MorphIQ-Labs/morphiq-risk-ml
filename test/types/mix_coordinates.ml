(* A normal (Bachelier) volatility cannot price a lognormal model. *)
open Morphiq_risk

let _ =
  let a = Result.get_ok (Black.Bsm.admit { spot = 1.; strike = 1.; time_to_expiry = 1.; rate = 0.; dividend_yield = 0. }) in
  Black.Bsm.price a Side.Call (Result.get_ok (Vol.normal 0.2))
