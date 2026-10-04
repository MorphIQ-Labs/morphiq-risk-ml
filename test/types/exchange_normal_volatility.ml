open Morphiq_risk

let asset (volatility : Vol.normal Vol.t) =
  Exchange.{ spot = 100.; dividend_yield = 0.; volatility }
