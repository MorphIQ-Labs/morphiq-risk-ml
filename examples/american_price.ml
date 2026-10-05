open Morphiq_risk
module A = Early_exercise.Bsm

let require = function
  | Ok value -> value
  | Error _ -> failwith "invalid example setup"

let () =
  let volatility = require (Vol.lognormal 0.2) in
  let contract =
    require
      (A.admit
         {
           spot = 100.;
           strike = 100.;
           rate = 0.05;
           dividend_yield = 0.02;
           time_to_expiry = 1.;
           opens_at = 0.;
           volatility;
         })
  in
  let limits =
    A.
      {
        max_nodes = 8192;
        max_steps = 32768;
        max_policy_solves = 262144;
        max_row_visits = 400000000;
        max_workspace_bytes = 8388608;
        policy_iterations = 32;
      }
  in
  (* Illustrative engineering criterion, not a numerical error certificate
     or a deployment recommendation. Choose budgets appropriate to the request. *)
  let configuration =
    require
      (A.configure ~tolerance:1. ~space_cells:128 ~time_steps:256
         ~domain_expansions:2 ~limits)
  in
  match
    A.price ~premium:true ~exercise_regions:true configuration contract Side.Put
  with
  | Ok estimate -> (
      Printf.printf
        "Estimated American put: %.12g (%s); %d accepted time steps\n"
        estimate.value estimate.method_name estimate.work.steps;
      match estimate.early_exercise_premium with
      | A.Available p ->
          Printf.printf "Estimated early-exercise premium: %.12g\n" p.value
      | A.Unavailable reason -> Printf.printf "Premium unavailable: %s\n" reason
      | A.Not_requested -> ())
  | Error (A.Resource_limit resource) ->
      Printf.eprintf "Resource limit: %s\n" resource;
      exit 1
  | Error A.Cancelled ->
      prerr_endline "Cancelled";
      exit 1
  | Error (A.Arithmetic_unresolved reason) ->
      Printf.eprintf "Arithmetic unresolved: %s\n" reason;
      exit 1
  | Error A.Unrepresentable ->
      prerr_endline "Unrepresentable computation";
      exit 1
  | Error (A.Nonconvergence _) ->
      prerr_endline "Policy solve did not converge";
      exit 1
  | Error (A.Accuracy_not_demonstrated _) ->
      prerr_endline "Refinement criterion not met";
      exit 1
