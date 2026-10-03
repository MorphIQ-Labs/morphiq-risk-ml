open Morphiq_risk
module P = Planner

let ok = function Ok x -> x | Error _ -> failwith "unexpected rejection"
let check b s = if not b then failwith s
let price = [ P.Output (Production.Price, 0.) ]

let limits =
  P.
    {
      max_instruments = 10;
      max_scenarios = 10;
      max_calculations = 100;
      tile_rows = 1;
      max_workers = 3;
      max_buffered_results = 6;
      max_groups = 10;
    }

let position id quantity forward =
  P.
    {
      id;
      factor = forward;
      rate_factor = "USD-flat";
      currency = "USD";
      quantity;
      model = Bachelier;
      strike = 0.;
      expiry_day = 0;
      rate = 0.;
      side = Side.Call;
    }

let plan portfolio market =
  ok
    (P.compile ~snapshot_id:"adversarial" ~base_day:0
       ~day_count:P.Actual_365_fixed ~portfolio ~market
       ~scenarios:(ok (Scenario.cartesian []))
       ~lognormal_outputs:[] ~normal_outputs:price ~output_mode:P.Stream ~limits)

let factor name forward =
  P.
    {
      name;
      market = Normal_market { forward; volatility = ok (Vol.normal 0.) };
    }

let run t =
  let events = ref [] in
  let result =
    P.execute t ~workers:3 ~cancellation:(P.cancellation ()) ~sink:(fun e ->
        events := e :: !events;
        Ok ())
  in
  check (result.stop = P.Complete) "failed execution";
  List.rev !events

let summary events =
  List.find_map (function P.Summary s -> Some s | _ -> None) events
  |> Option.get

let () =
  (* Product underflow is covered by the aggregation radius, not silently zeroed. *)
  let tiny = Float.next_after 0. 1. in
  let s =
    summary (run (plan [| position "a" 0.5 "n" |] [| factor "n" tiny |]))
  in
  let total = Option.get s.successful_subset in
  let exact = Q.mul (Q.of_float tiny) (Q.of_float 0.5) in
  check
    (Q.compare
       (Q.abs (Q.sub (Q.of_float total.value) exact))
       (Q.of_float total.absolute_error)
    <= 0)
    "weighted subnormal error";
  (* Exact mixed-sign cancellation across binary64 scales. *)
  let s =
    summary
      (run
         (plan
            [|
              position "a" 1e300 "n";
              position "b" 1. "n";
              position "c" (-1e300) "n";
            |]
            [| factor "n" 1. |]))
  in
  check s.complete "cancelling total incomplete";
  let total = Option.get s.successful_subset in
  check
    (Q.compare
       (Q.abs (Q.sub (Q.of_float total.value) Q.one))
       (Q.of_float total.absolute_error)
    <= 0)
    "lost small contribution";
  (* Intermediate overflow stays unresolved even if a later weight cancels. *)
  let s =
    summary
      (run
         (plan
            [|
              position "a" Float.max_float "n";
              position "b" (-.Float.max_float) "n";
            |]
            [| factor "n" 2. |]))
  in
  check
    ((not s.complete) && s.successful = 2 && s.failed = 0
   && s.successful_subset = None)
    "overflow accepted";
  let calls = ref 0 in
  let t = plan [| position "a" 1. "n" |] [| factor "n" 1. |] in
  let r =
    P.execute t ~workers:0 ~cancellation:(P.cancellation ()) ~sink:(fun _ ->
        incr calls;
        Ok ())
  in
  check
    (r.rows_committed = 0
    && (match r.stop with P.Worker_failure _ -> true | _ -> false)
    && !calls = 1)
    "invalid workers";
  (* A summary sink failure retains the committed-row prefix but cannot declare completion. *)
  let r =
    P.execute t ~workers:1 ~cancellation:(P.cancellation ()) ~sink:(function
      | P.Summary _ -> Error "summary write"
      | _ -> Ok ())
  in
  check
    (r.rows_committed = 1 && r.stop = P.Sink_failure "summary write")
    "summary failure transaction";
  let r =
    P.execute t ~workers:1 ~cancellation:(P.cancellation ()) ~sink:(function
      | P.Finished _ -> Error "marker write"
      | _ -> Ok ())
  in
  check
    (r.rows_committed = 1 && r.stop = P.Sink_failure "marker write")
    "completion marker failure";
  Printf.printf
    "planner adversarial: subnormal multiplication, cancellation, overflow and \
     output transactions passed\n"
