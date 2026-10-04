open Morphiq_risk
module P = Planner_instrumented
module F = P.Fast
module Q = Planner_probe

let ok = function Ok x -> x | Error _ -> failwith "metrics refusal"
let check b s = if not b then failwith s

let run scenarios workers =
  let sigma = ok (Vol.lognormal 0.2) in
  let portfolio =
    Array.init 8 (fun i ->
        P.
          {
            id = string_of_int i;
            factor = "F";
            rate_factor = "r";
            currency = "USD";
            quantity = 1.;
            model = Black76;
            strike = 100.;
            expiry_day = 365;
            rate = 0.02;
            side = (if i mod 2 = 0 then Side.Call else Side.Put);
          })
  in
  let market =
    [|
      P.
        {
          name = "F";
          market = Forward_market { forward = 100.; volatility = sigma };
        };
    |]
  in
  let scenarios_spec =
    ok
      (Scenario.cartesian
         [
           Scenario.Market
             {
               factor = "F";
               field = Forward;
               mode = Absolute;
               range =
                 ok (Scenario.linear ~first:100. ~step:1e-8 ~count:scenarios);
             };
         ])
  in
  let plan =
    ok
      (F.compile ~snapshot_id:"memory" ~base_day:0 ~day_count:P.Actual_365_fixed
         ~portfolio ~market ~scenarios:scenarios_spec
         ~limits:
           {
             max_instruments = 8;
             max_scenarios = scenarios;
             max_calculations = scenarios * 8;
             tile_rows = 4;
             max_workers = 4;
             max_buffered_results = 16;
           })
  in
  Q.reset ();
  Gc.full_major ();
  let before_live = (Gc.stat ()).live_words in
  let peak_live = ref before_live and rows = ref 0 in
  let before = Q.allocated_bytes () in
  let result =
    F.execute plan ~workers ~cancellation:(P.cancellation ()) ~sink:(function
      | F.Row r ->
          check (Result.is_ok r.price) "metrics price failed";
          incr rows;
          if !rows = 1 || !rows mod 4000 = 0 then (
            Gc.full_major ();
            peak_live := max !peak_live (Gc.stat ()).live_words);
          Ok ()
      | F.Finished _ -> Ok ())
  in
  let bytes = Q.allocated_bytes () - before + Atomic.get Q.worker_bytes in
  check (result.stop = P.Complete && !rows = scenarios * 8) "metrics coverage";
  check
    (Atomic.get Q.spawned = Atomic.get Q.joined && Atomic.get Q.active = 0)
    "unjoined worker";
  check
    (Atomic.get Q.peak_slots <= (F.explain plan).buffered_results
    && Atomic.get Q.retained_slots = 0)
    "unbounded wave";
  Printf.printf
    "{\"scenarios\":%d,\"workers\":%d,\"rows\":%d,\"peak_slots\":%d,\"bound\":%d,\"live_before\":%d,\"peak_live_sample\":%d,\"all_domain_bytes\":%d,\"source_sha256\":%S}\n\
     %!"
    scenarios workers !rows (Atomic.get Q.peak_slots)
    (F.explain plan).buffered_results before_live !peak_live bytes
    P.instrumented_source_sha256

let () =
  let checking = ref false and count = ref 8000 and workers = ref 1 in
  Arg.parse
    [
      ("--check", Arg.Set checking, "Run bounded-slot controls");
      ("--scenarios", Arg.Set_int count, "Scenario count");
      ("--workers", Arg.Set_int workers, "Worker count");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "fast-metrics-v1";
            exit 0),
        "Version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Fast planner allocation/memory probes";
  if !count < 1 || !count > 1000000 || !workers < 1 || !workers > 4 then
    failwith "metrics argument outside supported range";
  if !checking then List.iter (fun n -> List.iter (run n) [ 1; 4 ]) [ 8; 80 ]
  else run !count !workers
