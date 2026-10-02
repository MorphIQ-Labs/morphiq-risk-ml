(* A Black vega (per unit lognormal volatility) and a Bachelier vega (per
   unit normal volatility) cannot be combined. *)
open Morphiq_risk

let net (a : 'c Units.per_volatility) (b : 'c Units.per_volatility) =
  (a : 'c Units.per_volatility :> float)
  +. (b : 'c Units.per_volatility :> float)

let _ =
  let black =
    Result.get_ok
      (Black.Bsm.admit
         {
           spot = 1.;
           strike = 1.;
           time_to_expiry = 1.;
           rate = 0.;
           dividend_yield = 0.;
         })
  in
  let normal =
    Result.get_ok
      (Bachelier.admit
         { forward = 1.; strike = 1.; time_to_expiry = 1.; rate = 0. })
  in
  let gb =
    Black.Bsm.greeks black Side.Call (Result.get_ok (Vol.lognormal 0.2))
  in
  let gn = Bachelier.greeks normal Side.Call (Result.get_ok (Vol.normal 0.2)) in
  net (Result.get_ok gb.vega) (Result.get_ok gn.vega)
