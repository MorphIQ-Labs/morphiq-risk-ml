(* An admitted contract cannot be built except through admission. *)
open Morphiq_risk

let (_ : Black.Bsm.admitted) =
  Black.Coordinates.Expiry { spot = 1.; strike = 1. }
