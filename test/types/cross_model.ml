(* A contract admitted by BSM cannot be priced by Black-76. *)
open Morphiq_risk

let _ =
  let a = Result.get_ok (Black.Bsm.admit { spot = 1.; strike = 1.; time_to_expiry = 1.; rate = 0.; dividend_yield = 0. }) in
  Black.Black76.price a Side.Call (Result.get_ok (Vol.lognormal 0.2))
