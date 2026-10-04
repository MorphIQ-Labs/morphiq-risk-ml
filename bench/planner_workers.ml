open Morphiq_risk
module P = Planner
module F = P.Fast

external monotonic : unit -> float = "morphiq_bench_monotonic"

let ok = function Ok x -> x | Error _ -> failwith "benchmark refusal"
let lv = ok (Vol.lognormal 0.2)
let nv = ok (Vol.normal 2.)

let market =
  P.
    [|
      { name = "S"; market = Spot_market { spot = 100.; volatility = lv } };
      {
        name = "F";
        market = Forward_market { forward = 100.; volatility = lv };
      };
      { name = "D"; market = Forward_market { forward = -2.; volatility = lv } };
      { name = "N"; market = Normal_market { forward = -2.; volatility = nv } };
    |]

let scenarios = ok (Scenario.cartesian [ Scenario.Time [| 0; 7; 30; 90 |] ])

let position i =
  let factor, model, strike =
    match i mod 4 with
    | 0 -> ("S", P.Bsm { dividend_yield = 0.01 }, 95.)
    | 1 -> ("F", P.Black76, 95.)
    | 2 -> ("D", P.Displaced 5., -1.)
    | _ -> ("N", P.Bachelier, -1.)
  in
  P.
    {
      id = string_of_int i;
      factor;
      model;
      strike;
      rate_factor = "r";
      currency = "USD";
      quantity = 1.;
      expiry_day = 365;
      rate = 0.02;
      side = (if i / 4 mod 2 = 0 then Side.Call else Side.Put);
    }

(* This harness compares configurations of one unchanged runtime. It does not
   select a deployment policy or infer total allocation from coordinator GC. *)
let size = ref 1024
let tile_rows = ref 32
let mode = ref "fast"
let samples = ref 5
let warmups = ref 3
let iterations = ref 1
let workers = [ 1; 2; 4 ]

let verify_status n c =
  if
    c.P.stop <> P.Complete
    || c.rows_committed <> n * 4
    || c.calculations_committed <> n * 4
  then failwith "incomplete benchmark execution"

let digest events status =
  Digest.BLAKE256.to_hex
    (Digest.BLAKE256.string
       (Marshal.to_string (List.rev events, status) [ Marshal.No_sharing ]))

let fast portfolio =
  let compile () =
    ok
      (F.compile ~snapshot_id:"worker-crossover-v1" ~base_day:0
         ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
         ~limits:
           {
             max_instruments = !size;
             max_scenarios = 4;
             max_calculations = !size * 4;
             tile_rows = !tile_rows;
             max_workers = 4;
             max_buffered_results = !tile_rows * 4;
           })
  in
  let plan = compile () in
  let trace w =
    let events = ref [] in
    let c =
      F.execute plan ~workers:w ~cancellation:(P.cancellation ())
        ~sink:(fun event ->
          (match event with
          | F.Row row ->
              if Result.is_error row.price then failwith "ordinary fast refusal"
          | F.Finished _ -> ());
          events := event :: !events;
          Ok ())
    in
    verify_status !size c;
    digest !events c
  in
  let run first w =
    let c =
      F.execute plan ~workers:w ~cancellation:(P.cancellation ())
        ~sink:(fun event ->
          (match event with
          | F.Row _ when !first = 0. -> first := monotonic ()
          | _ -> ());
          Ok ())
    in
    verify_status !size c
  in
  let ex = F.explain plan in
  ( trace,
    run,
    ex.tiles,
    ex.buffered_results,
    fun () -> ignore (Sys.opaque_identity (compile ())) )

let certified portfolio =
  let compile () =
    ok
      (P.compile ~snapshot_id:"worker-crossover-v1" ~base_day:0
         ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
         ~lognormal_outputs:[ P.Output (Production.Price, 1e-8) ]
         ~normal_outputs:[ P.Output (Production.Price, 1e-8) ]
         ~output_mode:P.Stream
         ~limits:
           {
             max_instruments = !size;
             max_scenarios = 4;
             max_calculations = !size * 4;
             tile_rows = !tile_rows;
             max_workers = 4;
             max_buffered_results = !tile_rows * 4;
             max_groups = !size * 4;
           })
  in
  let plan = compile () in
  let trace w =
    let events = ref [] in
    let c =
      P.execute plan ~workers:w ~cancellation:(P.cancellation ())
        ~sink:(fun event ->
          (match event with
          | P.Row row ->
              List.iter
                (fun (P.Outcome (_, result)) ->
                  if Result.is_error result then
                    failwith "ordinary certified refusal")
                row.outcomes
          | _ -> ());
          events := event :: !events;
          Ok ())
    in
    verify_status !size c;
    digest !events c
  in
  let run first w =
    let c =
      P.execute plan ~workers:w ~cancellation:(P.cancellation ())
        ~sink:(fun event ->
          (match event with
          | P.Row _ when !first = 0. -> first := monotonic ()
          | _ -> ());
          Ok ())
    in
    verify_status !size c
  in
  let ex = P.explain plan in
  ( trace,
    run,
    ex.tiles,
    ex.buffered_results,
    fun () -> ignore (Sys.opaque_identity (compile ())) )

let sample ?(repeat = !iterations) phase workers round f =
  Gc.full_major ();
  let first = ref 0. in
  let gc0 = Gc.quick_stat () in
  let a0, b0, c0 = Gc.counters () in
  let cpu0 = Sys.time () and start = monotonic () in
  for _ = 1 to repeat do
    f first ()
  done;
  let elapsed = monotonic () -. start and cpu = Sys.time () -. cpu0 in
  let a1, b1, c1 = Gc.counters () in
  let gc1 = Gc.quick_stat () in
  let divisor = float repeat in
  Printf.printf
    "{\"kind\":\"sample\",\"phase\":%S,\"workers\":%d,\"round\":%d,\"iterations\":%d,\"wall_ns\":%.3f,\"cpu_ns\":%.3f,\"coordinator_bytes\":%.3f,\"coordinator_minor_collections\":%d,\"major_collections\":%d,\"first_row_ns\":%.3f}\n\
     %!"
    phase workers round repeat
    (elapsed *. 1e9 /. divisor)
    (cpu *. 1e9 /. divisor)
    (8. *. (a1 +. c1 -. b1 -. a0 -. c0 +. b0) /. divisor)
    (gc1.minor_collections - gc0.minor_collections)
    (gc1.major_collections - gc0.major_collections)
    (if !first = 0. then 0. else (!first -. start) *. 1e9)

let () =
  Arg.parse
    [
      ( "--mode",
        Arg.Symbol ([ "fast"; "certified" ], fun x -> mode := x),
        "Pricing mode" );
      ("--size", Arg.Set_int size, "Positions (four time scenarios)");
      ("--tile-rows", Arg.Set_int tile_rows, "Rows per tile");
      ("--samples", Arg.Set_int samples, "Samples per worker count");
      ("--warmups", Arg.Set_int warmups, "Warmups per worker count");
      ("--iterations", Arg.Set_int iterations, "Executions per sample");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "planner-workers-v1";
            exit 0),
        "Print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Planner worker/tile crossover benchmark";
  if
    List.exists
      (fun x -> x < 1 || x > 1000000)
      [ !size; !tile_rows; !samples; !iterations ]
    || !warmups < 0 || !warmups > 1000000
  then invalid_arg "benchmark argument outside supported range";
  let portfolio = Array.init !size position in
  let trace, run, tiles, bound, compile =
    if !mode = "fast" then fast portfolio else certified portfolio
  in
  let expected = trace 1 in
  List.iter
    (fun w -> if trace w <> expected then failwith "worker replay differs")
    workers;
  Printf.printf
    "{\"kind\":\"config\",\"mode\":%S,\"size\":%d,\"tile_rows\":%d,\"tiles\":%d,\"slot_bound\":%d,\"samples\":%d,\"warmups\":%d,\"iterations\":%d,\"digest\":%S}\n\
     %!"
    !mode !size !tile_rows tiles bound !samples !warmups !iterations expected;
  for _ = 1 to !warmups do
    compile ();
    List.iter (fun w -> run (ref 0.) w) workers
  done;
  for w = 2 to 4 do
    if w = 2 || w = 4 then
      for round = 1 to !samples do
        sample ~repeat:100 "empty-wave" w round (fun _ () ->
            let handles = ref [] in
            Fun.protect
              ~finally:(fun () -> List.iter Domain.join !handles)
              (fun () ->
                for _ = 2 to w do
                  handles := Domain.spawn (fun () -> ()) :: !handles
                done))
      done
  done;
  for round = 1 to !samples do
    sample "compile" 0 round (fun _ () -> compile ());
    List.iter
      (fun w -> sample "execute" w round (fun first () -> run first w))
      (if round mod 2 = 1 then workers else List.rev workers)
  done
