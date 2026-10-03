open Morphiq_risk
module P = Planner

let ok = function Ok x -> x | Error _ -> failwith "unexpected rejection"

let count = ref 1000
and workers = ref 1
and levels = ref 3
and expiry = ref false

let mode = ref "aggregate"
and tile_rows = ref 64

let () =
  Arg.parse
    [
      ("--instruments", Arg.Set_int count, "instrument count");
      ("--workers", Arg.Set_int workers, "worker count");
      ("--scenarios", Arg.Set_int levels, "scenario count");
      ("--tile-rows", Arg.Set_int tile_rows, "rows per tile");
      ( "--expiry",
        Arg.Set expiry,
        "measure expiry orchestration, not live pricing" );
      ("--mode", Arg.Set_string mode, "aggregate or stream");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "planner-scale-v1";
            exit 0),
        "print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "planner_scale [options]";
  if
    !count < 0 || !workers <= 0 || !levels < 1 || !tile_rows <= 0
    || not (List.mem !mode [ "aggregate"; "stream" ])
  then failwith "invalid arguments";
  let start = Unix.gettimeofday () in
  let sigma = ok (Vol.lognormal 0.2) in
  let market =
    [|
      P.
        {
          name = "F";
          market = Forward_market { forward = 100.; volatility = sigma };
        };
    |]
  in
  let portfolio =
    Array.init !count (fun i ->
        P.
          {
            id = string_of_int i;
            factor = "F";
            rate_factor = "USD-flat";
            currency = "USD";
            quantity = (if i mod 2 = 0 then 100. else -99.);
            model = Black76;
            strike = 95. +. float_of_int (i mod 11);
            expiry_day = (if !expiry then 0 else 365);
            rate = 0.02;
            side = (if i mod 3 = 0 then Side.Put else Call);
          })
  in
  let scenarios =
    ok
      (Scenario.cartesian
         [
           Scenario.Market
             {
               factor = "F";
               field = Forward;
               mode = Relative;
               range = ok (Scenario.linear ~first:0.9 ~step:0.1 ~count:!levels);
             };
         ])
  in
  let packed = Unix.gettimeofday () in
  let limits =
    P.
      {
        max_instruments = !count;
        max_scenarios = !levels;
        max_calculations = max_int;
        tile_rows = !tile_rows;
        max_workers = !workers;
        max_buffered_results = max_int;
        max_groups = 100;
      }
  in
  let plan =
    ok
      (P.compile ~snapshot_id:"scale-v1" ~base_day:0
         ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
         ~lognormal_outputs:[ P.Output (Production.Price, 1e-10) ]
         ~normal_outputs:[]
         ~output_mode:(if !mode = "stream" then P.Stream else Aggregate_only)
         ~limits)
  in
  let compiled = Unix.gettimeofday () in
  Gc.full_major ();
  let gc0 = Gc.quick_stat () in
  let rows = ref 0
  and failures = ref 0
  and summaries = ref 0
  and incomplete = ref 0 in
  let digest = Buffer.create 1024 in
  let output_time = ref 0. in
  let result =
    P.execute plan ~workers:!workers ~cancellation:(P.cancellation ())
      ~sink:(fun event ->
        let t = Unix.gettimeofday () in
        (match event with
        | P.Row row ->
            incr rows;
            List.iter
              (fun (P.Outcome (_, r)) ->
                if Result.is_error r then incr failures)
              row.outcomes
        | Summary s ->
            incr summaries;
            if not s.complete then incr incomplete;
            Buffer.add_string digest (Marshal.to_string s [])
        | Finished _ -> ());
        output_time := !output_time +. (Unix.gettimeofday () -. t);
        Ok ())
  in
  let finished = Unix.gettimeofday () and gc1 = Gc.quick_stat () in
  let ex = P.explain plan in
  Printf.printf
    "{\"version\":\"planner-scale-v1\",\"ocaml\":%S,\"instruments\":%d,\"scenarios\":%d,\"workers\":%d,\"tile_rows\":%d,\"expiry\":%b,\"mode\":%S,\"packing_s\":%.9g,\"planning_s\":%.9g,\"execution_s\":%.9g,\"sink_s\":%.9g,\"committed_rows\":%d,\"failures\":%d,\"summary_count\":%d,\"incomplete_summaries\":%d,\"buffered_results\":%d,\"allocated_words\":%.17g,\"minor_collections\":%d,\"major_collections\":%d,\"digest\":%S,\"complete\":%b}\n\
     %!"
    Sys.ocaml_version !count !levels !workers !tile_rows !expiry !mode
    (packed -. start) (compiled -. packed) (finished -. compiled) !output_time
    result.rows_committed !failures !summaries !incomplete ex.buffered_results
    (gc1.minor_words +. gc1.major_words -. gc1.promoted_words -. gc0.minor_words
   -. gc0.major_words +. gc0.promoted_words)
    (gc1.minor_collections - gc0.minor_collections)
    (gc1.major_collections - gc0.major_collections)
    (Digest.BLAKE256.to_hex (Digest.BLAKE256.string (Buffer.contents digest)))
    (result.stop = P.Complete);
  if result.stop <> P.Complete || !failures <> 0 || !incomplete <> 0 then exit 1
