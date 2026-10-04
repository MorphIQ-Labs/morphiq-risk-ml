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

let tile_rows = ref 32
let sizes = ref [ 32; 256; 1024 ]

let compile portfolio =
  let n = Array.length portfolio in
  ok
    (F.compile ~snapshot_id:"fast-planner-bench" ~base_day:0
       ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
       ~limits:
         {
           max_instruments = n;
           max_scenarios = 4;
           max_calculations = n * 4;
           tile_rows = !tile_rows;
           max_workers = 4;
           max_buffered_results = !tile_rows * 4;
         })

let execute workers plan =
  let status =
    F.execute plan ~workers ~cancellation:(P.cancellation ()) ~sink:(function
      | F.Row r ->
          ignore (Sys.opaque_identity r);
          Ok ()
      | F.Finished _ -> Ok ())
  in
  if status.stop <> P.Complete then failwith "incomplete execution"

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let sample n phase f =
  let iterations = max 1 (4096 / n) in
  for _ = 1 to 3 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for k = 1 to 5 do
    Gc.full_major ();
    let before = words () and cpu = Sys.time () and start = monotonic () in
    for _ = 1 to iterations do
      ignore (Sys.opaque_identity (f ()))
    done;
    let elapsed = monotonic () -. start in
    let cpu = Sys.time () -. cpu and bytes = 8. *. (words () -. before) in
    Printf.printf "TIME %d %s %d %.3f %.3f %.3f\n%!" n phase k
      (elapsed *. 1e9 /. float iterations)
      (cpu *. 1e9 /. float iterations)
      (bytes /. float iterations)
  done

let () =
  Arg.parse
    [
      ("--tile-rows", Arg.Set_int tile_rows, "Rows per tile");
      ("--size", Arg.Int (fun n -> sizes := [ n ]), "Positions per job");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "fast-planner-v1";
            exit 0),
        "Print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Fast scenario planner phase benchmark";
  if
    !tile_rows < 1 || !tile_rows > 1000000
    || List.exists (fun n -> n < 1 || n > 1000000) !sizes
  then invalid_arg "benchmark size";
  List.iter
    (fun n ->
      let portfolio = Array.init n position in
      let plan = compile portfolio in
      let trace workers =
        let rows = ref [] in
        let c =
          F.execute plan ~workers ~cancellation:(P.cancellation ())
            ~sink:(function
            | F.Row r ->
                if Result.is_error r.price then failwith "ordinary row failed";
                rows := r :: !rows;
                Ok ()
            | F.Finished _ -> Ok ())
        in
        if c.stop <> P.Complete || c.rows_committed <> n * 4 then
          failwith "missing rows";
        Marshal.to_string (List.rev !rows, c) [ Marshal.No_sharing ]
      in
      let expected = trace 1 in
      if trace 4 <> expected then failwith "worker outcome mismatch";
      Printf.printf "CHECK %d %s\n%!" n (Digest.to_hex (Digest.string expected));
      sample n "compile" (fun () -> compile portfolio);
      sample n "execute-1" (fun () -> execute 1 plan);
      sample n "execute-4" (fun () -> execute 4 plan);
      sample n "pack-compile-execute" (fun () ->
          execute 1 (compile (Array.init n position))))
    !sizes
