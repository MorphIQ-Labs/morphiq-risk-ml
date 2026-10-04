open Morphiq_risk
module P = Planner

external monotonic : unit -> float = "morphiq_bench_monotonic"

let ok = function Ok x -> x | Error s -> failwith s

let allocated_words () =
  let minor, promoted, major = Gc.counters () in
  minor +. major -. promoted

let count = ref 5000
let groups = ref 5000

let () =
  Arg.parse
    [
      ("--instruments", Arg.Set_int count, "number of positions");
      ("--groups", Arg.Set_int groups, "distinct rate-factor groups");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "planner-compile-v1";
            exit 0),
        "print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "planner_compile [options]";
  if !count <= 0 || !groups <= 0 || !groups > !count then
    invalid_arg "require 0 < groups <= instruments";
  let control = allocated_words () in
  ignore (Sys.opaque_identity (Array.make 10000 0.));
  if allocated_words () -. control < 10001. then
    failwith "allocation counter misses a known allocation";
  let market =
    [|
      P.
        {
          name = "F";
          market =
            Forward_market
              { forward = 100.; volatility = Result.get_ok (Vol.lognormal 0.2) };
        };
    |]
  in
  let portfolio =
    Array.init !count (fun i ->
        P.
          {
            id = string_of_int i;
            factor = "F";
            rate_factor = string_of_int (i mod !groups);
            currency = "USD";
            quantity = 1.;
            model = Black76;
            strike = 100.;
            expiry_day = 0;
            rate = 0.;
            side = Side.Call;
          })
  in
  let scenarios = ok (Scenario.cartesian []) in
  let limits =
    P.
      {
        max_instruments = !count;
        max_scenarios = 1;
        max_calculations = !count;
        tile_rows = 100;
        max_workers = 1;
        max_buffered_results = 100;
        max_groups = !count;
      }
  in
  let compile () =
    ok
      (P.compile ~snapshot_id:"compile-benchmark-v1" ~base_day:0
         ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
         ~lognormal_outputs:[ P.Output (Production.Price, 1e-10) ]
         ~normal_outputs:[] ~output_mode:P.Aggregate_only ~limits)
  in
  let check_plan plan =
    let ex = P.explain plan in
    if
      ex.groups <> !groups || ex.instruments <> !count
      || ex.calculations <> !count
    then failwith "wrong compiled counts"
  in
  check_plan (compile ());
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let words_before = allocated_words () in
  let start = monotonic () in
  let plan = compile () in
  let elapsed = monotonic () -. start in
  let words_after = allocated_words () in
  let after = Gc.quick_stat () in
  check_plan plan;
  Printf.printf
    "{\"version\":\"planner-compile-v1\",\"ocaml\":%S,\"instruments\":%d,\"groups\":%d,\"planning_s\":%.17g,\"allocated_words\":%.17g,\"minor_collections\":%d,\"major_collections\":%d,\"plan_id\":%S}\n"
    Sys.ocaml_version !count !groups elapsed
    (words_after -. words_before)
    (after.minor_collections - before.minor_collections)
    (after.major_collections - before.major_collections)
    (P.explain plan).plan_id
