(* A per-calendar-day theta cannot be used as an annual rate without
   Units.annualise. *)
open Morphiq_risk

let annual_carry (rate : Units.per_year Units.time_rate) = rate

let _ =
  let a = Result.get_ok (Black.Bsm.admit { spot = 1.; strike = 1.; time_to_expiry = 1.; rate = 0.; dividend_yield = 0. }) in
  let g = Black.Bsm.greeks a Side.Call (Result.get_ok (Vol.lognormal 0.2)) in
  annual_carry (Result.get_ok g.theta)
