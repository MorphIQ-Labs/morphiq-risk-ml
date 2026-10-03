open Morphiq_risk

let sigma = match Vol.normal 1. with Ok x -> x | Error _ -> assert false

let request =
  Batch.Request
    ( Batch.Bsm,
      Black.Bsm_carry.
        {
          spot = 100.;
          strike = 100.;
          time_to_expiry = 1.;
          rate = 0.;
          dividend_yield = 0.;
        },
      Side.Call,
      Batch.Evaluate (sigma, Production.Price, 1e-10) )
