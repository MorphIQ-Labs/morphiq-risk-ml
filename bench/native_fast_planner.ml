open Morphiq_risk
module P = Planner
module F = P.Fast

external clock : unit -> float = "morphiq_bench_monotonic"

let ok = function Ok x -> x | Error _ -> failwith "benchmark refusal"
let lv = ok (Vol.lognormal 0.2)
let nv = ok (Vol.normal 10.)
let days = [| 0; 7; 30; 90 |]
let scenarios = ok (Scenario.cartesian [ Scenario.Time days ])
let families = [ "eligible"; "mixed"; "fallback-heavy" ]

let configurations =
  [ (32, 32); (256, 32); (256, 256); (4096, 256); (4096, 1024) ]

let market =
  P.
    [|
      { name = "N"; market = Normal_market { forward = 100.; volatility = nv } };
      { name = "S"; market = Spot_market { spot = 100.; volatility = lv } };
      {
        name = "F";
        market = Forward_market { forward = 100.; volatility = lv };
      };
      { name = "D"; market = Forward_market { forward = -2.; volatility = lv } };
    |]

let position family i =
  let side = if i mod 2 = 0 then Side.Call else Side.Put in
  let q =
    if family = "fallback-heavy" then
      match i mod 4 with 0 -> 0. | 1 -> 8. | 2 -> -1. | _ -> 1.
    else 0.5 +. (float (i mod 32) /. 16.)
  in
  let factor, model, strike =
    if family = "mixed" && i mod 4 <> 3 then
      match i mod 4 with
      | 0 -> ("S", P.Bsm { dividend_yield = 0.01 }, 95.)
      | 1 -> ("F", P.Black76, 105.)
      | _ -> ("D", P.Displaced 10., -1.)
    else
      ( "N",
        P.Bachelier,
        100. +. if side = Side.Call then q *. 10. else -.q *. 10. )
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
      side;
    }

let request (p : P.position) day =
  let time_to_expiry = float (p.expiry_day - day) /. 365. in
  match p.model with
  | P.Bachelier ->
      Batch.Fast.Price
        ( Batch.Bachelier,
          { forward = 100.; strike = p.strike; time_to_expiry; rate = p.rate },
          p.side,
          nv )
  | P.Black76 ->
      Batch.Fast.Price
        ( Batch.Black76,
          { forward = 100.; strike = p.strike; time_to_expiry; rate = p.rate },
          p.side,
          lv )
  | P.Displaced displacement ->
      Batch.Fast.Price
        ( Batch.Displaced,
          {
            forward = -2.;
            strike = p.strike;
            time_to_expiry;
            rate = p.rate;
            displacement;
          },
          p.side,
          lv )
  | P.Bsm { dividend_yield } ->
      Batch.Fast.Price
        ( Batch.Bsm,
          {
            spot = 100.;
            strike = p.strike;
            time_to_expiry;
            rate = p.rate;
            dividend_yield;
          },
          p.side,
          lv )

let compile portfolio tile_rows =
  let n = Array.length portfolio in
  ok
    (F.compile ~snapshot_id:"native-tile-measurement" ~base_day:0
       ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
       ~limits:
         {
           max_instruments = n;
           max_scenarios = 4;
           max_calculations = n * 4;
           tile_rows;
           max_workers = 4;
           max_buffered_results = tile_rows * 4;
         })

let signature = function
  | Ok value -> Printf.sprintf "%016Lx" (Int64.bits_of_float value)
  | Error _ -> failwith "unexpected ordinary benchmark failure"

let trace family portfolio plan workers emit =
  let buffer = Buffer.create 1024 in
  let status =
    F.execute plan ~workers ~cancellation:(P.cancellation ()) ~sink:(function
      | F.Row row ->
          let expected =
            Result.map_error
              (fun e -> F.Scalar e)
              (Batch.Fast.evaluate
                 (request
                    portfolio.(row.instrument_index)
                    days.(row.scenario_id)))
          in
          if signature row.price <> signature expected then
            failwith "benchmark scalar replay";
          let line =
            Printf.sprintf "%s %d %d %d %s\n" family (Array.length portfolio)
              row.scenario_id row.instrument_index (signature row.price)
          in
          Buffer.add_string buffer line;
          if emit then print_string line;
          Ok ()
      | F.Finished _ -> Ok ())
  in
  if
    status.stop <> P.Complete
    || status.rows_committed <> 4 * Array.length portfolio
  then failwith "benchmark coverage";
  Digest.to_hex (Digest.string (Buffer.contents buffer))

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let job portfolio tile workers compiled =
  let start = clock () in
  let plan =
    match compiled with Some p -> p | None -> compile portfolio tile
  in
  let first = ref None in
  let completion =
    F.execute plan ~workers ~cancellation:(P.cancellation ()) ~sink:(function
      | F.Row row ->
          if !first = None then first := Some (clock () -. start);
          ignore (Sys.opaque_identity row);
          Ok ()
      | F.Finished _ -> Ok ())
  in
  if completion.stop <> P.Complete then failwith "incomplete timed job";
  Option.get !first

let benchmark reverse =
  let configurations =
    if reverse then List.rev configurations else configurations
  in
  List.iter
    (fun family ->
      List.iter
        (fun (n, tile) ->
          let portfolio = Array.init n (position family) in
          let plan = compile portfolio tile in
          let worker_counts = if reverse then [ 4; 2; 1 ] else [ 1; 2; 4 ] in
          List.iter
            (fun workers ->
              let digest = trace family portfolio plan workers false in
              Printf.printf "CHECK %s %d %d %d %s\n%!" family n tile workers
                digest;
              List.iter
                (fun (phase, compiled) ->
                  let run () = job portfolio tile workers compiled in
                  for _ = 1 to 3 do
                    ignore (run ())
                  done;
                  let iterations = max 1 (1024 / n) in
                  for sample = 1 to 5 do
                    Gc.full_major ();
                    let before = words ()
                    and cpu = Sys.time ()
                    and start = clock () in
                    let first = ref 0. in
                    for _ = 1 to iterations do
                      first := !first +. run ()
                    done;
                    let elapsed = clock () -. start in
                    let cpu = Sys.time () -. cpu
                    and bytes = 8. *. (words () -. before) in
                    Printf.printf
                      "TIME %s %d %d %d %s %d %.9g %.9g %.9g %.9g\n%!" family n
                      tile workers phase sample
                      (elapsed *. 1e9 /. float iterations)
                      (cpu *. 1e9 /. float iterations)
                      (bytes /. float iterations)
                      (!first *. 1e9 /. float iterations)
                  done)
                [ ("execute", Some plan); ("compile-execute", None) ])
            worker_counts)
        configurations)
    families

let dump () =
  List.iter
    (fun family ->
      let portfolio = Array.init 4096 (position family) in
      Array.iter
        (fun day ->
          Array.iter
            (fun position ->
              let (Batch.Fast.Price (model, inputs, side, vol)) =
                request position day
              in
              let name, f, k, t, r, q, shift =
                match model with
                | Batch.Bachelier ->
                    ( "bachelier",
                      inputs.forward,
                      inputs.strike,
                      inputs.time_to_expiry,
                      inputs.rate,
                      0.,
                      0. )
                | Batch.Black76 ->
                    ( "black76",
                      inputs.forward,
                      inputs.strike,
                      inputs.time_to_expiry,
                      inputs.rate,
                      0.,
                      0. )
                | Batch.Displaced ->
                    ( "displaced",
                      inputs.forward,
                      inputs.strike,
                      inputs.time_to_expiry,
                      inputs.rate,
                      0.,
                      inputs.displacement )
                | Batch.Bsm ->
                    ( "bsm",
                      inputs.spot,
                      inputs.strike,
                      inputs.time_to_expiry,
                      inputs.rate,
                      inputs.dividend_yield,
                      0. )
              in
              Printf.printf
                "%s %s benchmark timed-tiles-%s %s 0000000000000000\n" name
                (if side = Side.Call then "call" else "put")
                family
                (String.concat " "
                   (List.map
                      (fun v -> Printf.sprintf "%016Lx" (Int64.bits_of_float v))
                      [ f; k; t; r; q; Vol.to_float vol; shift ])))
            portfolio)
        days)
    families

let () =
  let mode = ref "bench" and reverse = ref false in
  Arg.parse
    [
      ( "--dump-inputs",
        Arg.Unit (fun () -> mode := "dump"),
        "Exact original timed inputs" );
      ( "--trace",
        Arg.Unit (fun () -> mode := "trace"),
        "Full untimed largest-book outcomes" );
      ("--reverse", Arg.Set reverse, "Reverse configuration/worker order");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "native-tiles-1";
            exit 0),
        "Version" );
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected argument")),
        "End options" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Native tile integration benchmark";
  match !mode with
  | "dump" -> dump ()
  | "trace" ->
      List.iter
        (fun family ->
          let p = Array.init 4096 (position family) in
          ignore (trace family p (compile p 256) 1 true))
        families
  | _ -> benchmark !reverse
