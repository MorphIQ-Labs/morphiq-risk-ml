open Morphiq_risk

let certify (result : Batch.Fast.outcome) : float Production.certified =
  Result.get_ok result
