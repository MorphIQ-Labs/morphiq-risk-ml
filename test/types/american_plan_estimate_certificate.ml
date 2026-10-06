open Morphiq_risk

let invalid (row : Planner.American.row) : Early_exercise.Bsm.Certified.price =
  match row.outcomes with
  | [ Planner.American.Outcome (Batch.American.Price _, Ok value) ] -> value
  | _ -> failwith "not a price"
