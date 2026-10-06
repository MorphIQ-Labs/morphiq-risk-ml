open Morphiq_risk
module A = Early_exercise.Bsm
module B = Batch.American
module P = Planner.American

external clock : unit -> float = "morphiq_bench_monotonic"

let get = function Ok x -> x | Error _ -> failwith "campaign refusal"
let vol x = get (Vol.lognormal x)

let cfg =
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

let price = B.Price { pricing = cfg; premium = false; exercise_regions = false }

let greeks =
  get
    (A.configure_greeks
       [
         get (A.request_greek ~tolerance:10. Delta);
         get (A.request_greek ~tolerance:10. Gamma);
       ])

let inverse =
  get
    (A.Implied_volatility.configure ~pricing:cfg ~lower:(vol 0.05)
       ~upper:(vol 0.6) ~width:0.01 ~max_evaluations:32)

let quote = get (A.Implied_volatility.quote 0x1.4e6b2e3d54dc2p+3)
let certificate = get (A.Certified.absolute_error_limit 1e-9)

let cases =
  [
    ("call", Side.Call, B.Output price);
    ("put", Side.Put, B.Output price);
    ("greeks", Side.Put, B.Output (B.Greeks (cfg, greeks)));
    ("iv", Side.Call, B.Output (B.Implied (inverse, quote)));
    ("certified", Side.Call, B.Output (B.Certified_price certificate));
  ]

let inputs spot =
  A.
    {
      spot;
      strike = 100.;
      rate = 0.05;
      dividend_yield = 0.;
      volatility = vol 0.2;
      time_to_expiry = 1.;
      opens_at = 0.;
    }

let limits =
  P.
    {
      max_instruments = 4;
      max_market_factors = 1;
      max_scenarios = 2;
      max_calculations = 8;
      tile_rows = 1;
      max_workers = 2;
      max_buffered_results = 2;
      max_solver_workspace_bytes = 8388608;
      max_schedule_events = 1;
    }

let batch_limits =
  B.{ max_requests = 8; max_outputs = 8; max_solver_workspace_bytes = 8388608 }

let scenarios =
  get
    (Scenario.paired
       Scenario.
         [|
           { offset_days = 0; shocks = [] };
           {
             offset_days = 0;
             shocks =
               [ { factor = "S"; field = Spot; adjustment = Replace 101. } ];
           };
         |])

let market = P.[| { name = "S"; spot = 100. } |]

let build side output =
  let portfolio =
    Array.init 4 (fun i ->
        P.Position
          {
            id = string_of_int i;
            factor = "S";
            currency = "USD";
            quantity = 1.;
            strike = 100.;
            expiry_day = 365;
            side;
            model =
              P.Constant
                { rate = 0.05; dividend_yield = 0.; volatility = vol 0.2 };
            exercise =
              P.American
                {
                  opening = { day = 0; side = A.Regular };
                  expiry_side = A.Regular;
                };
            cash = None;
            outputs = [ output ];
          })
  in
  let compile () =
    get
      (P.compile ~snapshot_id:"american-compiled-benchmark-v1" ~base_day:0
         ~day_count:Planner.Actual_365_fixed ~cash_at_valuation:P.Before_payment
         ~portfolio ~market ~scenarios ~limits)
  in
  let admissions =
    Array.init 8 (fun i ->
        get (A.admit (inputs (if i < 4 then 100. else 101.))))
  in
  let requests =
    Array.mapi
      (fun i a ->
        B.Request
          {
            id = string_of_int i;
            model = B.Constant a;
            side;
            outputs = [ output ];
          })
      admissions
  in
  ( admissions,
    (fun () -> get (B.compile ~limits:batch_limits requests)),
    compile )

let scalar side a (B.Output op : B.constant B.output) =
  let result : type v. (B.constant, v) B.operation -> (v, B.error) result =
    function
    | B.Price p ->
        Result.map_error
          (fun e -> B.Pricing e)
          (A.price ~premium:p.premium ~exercise_regions:p.exercise_regions
             p.pricing a side)
    | B.Greeks (c, g) ->
        Result.map_error (fun e -> B.Pricing e) (A.greeks c g a side)
    | B.Implied (s, q) ->
        Result.map_error
          (fun e -> B.Inverse e)
          (A.Implied_volatility.solve s a side q)
    | B.Certified_price limit ->
        Result.map_error
          (fun e -> B.Certification e)
          (A.Certified.price a side ~max_error:limit)
  in
  B.Outcome (op, result op)

let payload x = Marshal.to_string x [ Marshal.No_sharing ]

let check_outcome (B.Outcome (op, r)) =
  match (op, r) with
  | _, Error _ -> failwith "campaign output failed"
  | B.Greeks _, Ok g ->
      List.iter
        (function
          | _, A.Greek_estimate _ -> ()
          | _ -> failwith "unresolved campaign Greek")
        g.greeks
  | _, Ok _ -> ()

let run_plan plan workers sink =
  let c =
    P.execute plan ~workers ~cancellation:(Planner.cancellation ()) ~sink
  in
  if
    c.stop <> Planner.Complete || c.rows_committed <> 8
    || c.calculations_committed <> 8
  then failwith "incomplete campaign"

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let measure name mode n f =
  for _ = 1 to 2 do
    ignore (f ())
  done;
  Gc.full_major ();
  let w = words ()
  and gc = Gc.quick_stat ()
  and cpu = Sys.time ()
  and start = clock () in
  let first = ref 0. in
  for _ = 1 to n do
    first := !first +. f ()
  done;
  let wall = clock () -. start
  and cpu = Sys.time () -. cpu
  and alloc = (words () -. w) *. 8. in
  let after = Gc.quick_stat () in
  Printf.printf "SAMPLE\t%s\t%s\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%d\n%!" name
    mode n
    (wall /. float n)
    (cpu /. float n)
    (alloc /. float n)
    (!first /. float n)
    (after.minor_collections - gc.minor_collections)
    (after.major_collections - gc.major_collections)

let run reverse (name, side, output) =
  let admissions, compile_batch, compile_plan = build side output in
  let batch = compile_batch () and plan = compile_plan () in
  let reference = Array.map (fun a -> scalar side a output) admissions in
  Array.iter check_outcome reference;
  let fixed =
    Array.map (fun (r : B.row) -> List.hd r.outcomes) (B.execute batch)
  in
  if payload fixed <> payload reference then failwith "fixed batch mismatch";
  List.iter
    (fun workers ->
      let outcomes = ref [] in
      run_plan plan workers (function
        | P.Row r ->
            outcomes := List.hd r.outcomes :: !outcomes;
            Ok ()
        | P.Finished _ -> Ok ());
      let expected =
        Array.map
          (fun (B.Outcome (op, r)) ->
            P.Outcome (op, Result.map_error (fun e -> P.Scalar e) r))
          reference
      in
      if payload (Array.of_list (List.rev !outcomes)) <> payload expected then
        failwith "planner mismatch")
    [ 1; 2 ];
  Printf.printf
    "CHECK\t%s\t8 accepted; scalar/fixed/1-worker/2-worker identical\n%!" name;
  let planned workers () =
    let start = clock () and first = ref None in
    run_plan plan workers (function
      | P.Row _ ->
          if !first = None then first := Some (clock () -. start);
          Ok ()
      | P.Finished _ -> Ok ());
    Option.get !first
  in
  let modes =
    [
      ( "scalar",
        5,
        fun () ->
          Array.iter
            (fun a -> ignore (Sys.opaque_identity (scalar side a output)))
            admissions;
          0. );
      ( "batch",
        5,
        fun () ->
          ignore (Sys.opaque_identity (B.execute batch));
          0. );
      ("planner-1", 5, planned 1);
      ("planner-2", 5, planned 2);
      ( "compile-batch",
        100,
        fun () ->
          ignore (Sys.opaque_identity (compile_batch ()));
          0. );
      ( "compile-plan",
        100,
        fun () ->
          ignore (Sys.opaque_identity (compile_plan ()));
          0. );
    ]
  in
  List.iter
    (fun (mode, n, f) -> measure name mode n f)
    (if reverse then List.rev modes else modes)

let cancellation () =
  let _, _, compile = build Side.Put (B.Output price) in
  let plan = compile () and token = Planner.cancellation () in
  let start = clock () in
  let controller =
    Domain.spawn (fun () ->
        Unix.sleepf 0.005;
        let issued = clock () in
        Planner.cancel token;
        issued)
  in
  let result =
    P.execute plan ~workers:2 ~cancellation:token ~sink:(fun _ -> Ok ())
  in
  let finished = clock () in
  let issued = Domain.join controller in
  if result.stop <> Planner.Cancelled then
    failwith "cancellation probe finished before issuance";
  Printf.printf "CANCEL\t%.9g\t%.9g\t%d\t%d\n%!" (issued -. start)
    (finished -. issued) result.rows_committed result.calculations_committed

let () =
  let reverse =
    match Array.to_list Sys.argv with
    | [ _ ] | [ _; "--" ] -> false
    | [ _; "--reverse" ] -> true
    | [ _; ("--help" | "-h") ] ->
        print_endline
          "Usage: american_compiled [--reverse|--version] (fixed engineering \
           corpus)";
        exit 0
    | [ _; "--version" ] ->
        print_endline Morphiq_risk.version;
        exit 0
    | _ ->
        prerr_endline "Usage: american_compiled [--reverse|--help|--version]";
        exit 2
  in
  List.iter (run reverse) (if reverse then List.rev cases else cases);
  cancellation ()
