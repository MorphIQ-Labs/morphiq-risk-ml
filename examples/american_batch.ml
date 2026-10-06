open Morphiq_risk
module A = Early_exercise.Bsm
module B = Batch.American

let get = function Ok x -> x | Error _ -> failwith "example admission failed"

let () =
  let pricing =
    get
      (A.configure ~tolerance:1. ~space_cells:64 ~time_steps:64
         ~domain_expansions:2
         ~limits:
           A.
             {
               max_nodes = 8192;
               max_steps = 131072;
               max_policy_solves = 1048576;
               max_row_visits = 100000000;
               max_workspace_bytes = 8388608;
               policy_iterations = 64;
             })
  in
  let admitted =
    get
      (A.admit
         A.
           {
             spot = 100.;
             strike = 100.;
             rate = 0.05;
             dividend_yield = 0.;
             volatility = get (Vol.lognormal 0.2);
             time_to_expiry = 1.;
             opens_at = 0.;
           })
  in
  let batch =
    get
      (B.compile
         ~limits:
           {
             max_requests = 1;
             max_outputs = 2;
             max_solver_workspace_bytes = pricing.limits.max_workspace_bytes;
           }
         [|
           B.Request
             {
               id = "call-1";
               model = B.Constant admitted;
               side = Side.Call;
               outputs =
                 [
                   B.Output
                     (B.Price
                        { pricing; premium = false; exercise_regions = false });
                   B.Output
                     (B.Certified_price
                        (get (A.Certified.absolute_error_limit 1e-9)));
                 ];
             };
         |])
  in
  Array.iter
    (fun (row : B.row) ->
      List.iter
        (function
          | B.Outcome (B.Price _, Ok p) ->
              Printf.printf "%s estimated price: %.9g\n" row.id p.value
          | B.Outcome (B.Certified_price _, Ok p) ->
              Printf.printf "%s certified price: %.9g +/- %.3g\n" row.id p.value
                p.absolute_error
          | B.Outcome (_, Error _) -> failwith "requested example output failed"
          | _ -> failwith "unexpected example output")
        row.outcomes)
    (B.execute batch)
