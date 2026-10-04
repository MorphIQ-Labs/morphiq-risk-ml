open Morphiq_risk

let evaluate (plan : Planner.Fast.t) (tile : Planner.tile) =
  Planner.Fast.evaluate_tile plan tile
