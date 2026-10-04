(* Optional persistent-process operational probe. One process is one serial
   request client; the Python driver controls inter-process concurrency. *)
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

let size = ref 1024
let days = ref "0,7,30,90"
let tile_rows = ref 256
let workers = ref 1
let slots = ref 1024
let mode = ref "fast"
let outputs = ref "price"
let policy = ref "reuse"
let sink_mode = ref "count"
let allowance = ref 1e-8

let requests : type c. unit -> c P.output list =
 fun () ->
  let e = !allowance in
  let price = P.Output (Production.Price, e) in
  if !outputs = "price" then [ price ]
  else
    P.
      [
        price;
        Output (Production.Delta, e);
        Output (Production.Gamma, e);
        Output (Production.Rho, e);
        Output (Production.Theta, Units.time_rate e);
        Output (Production.Vega, Units.per_volatility e);
        Output (Production.Vanna, Units.per_volatility e);
        Output (Production.Volga, Units.per_volatility_squared e);
        Output (Production.Charm, Units.time_rate e);
        Output (Production.Veta, Units.volatility_time_rate e);
        Output (Production.Color, Units.time_rate e);
      ]

type plan = Fast of F.t | Certified of P.t

let checked_product a b =
  if a <> 0 && b > max_int / a then invalid_arg "workload overflow";
  a * b

let make () =
  let offsets =
    Array.of_list (List.map int_of_string (String.split_on_char ',' !days))
  in
  let scenarios = ok (Scenario.cartesian [ Scenario.Time offsets ]) in
  let count = if !outputs = "price" then 1 else 11 in
  let calculations =
    checked_product (checked_product !size (Array.length offsets)) count
  in
  let groups = checked_product !size count in
  let portfolio = Array.init !size position in
  if !mode = "fast" then
    Fast
      (ok
         (F.compile ~snapshot_id:"operational-mixed-v1" ~base_day:0
            ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
            ~limits:
              {
                max_instruments = !size;
                max_scenarios = Array.length offsets;
                max_calculations = calculations;
                tile_rows = !tile_rows;
                max_workers = !workers;
                max_buffered_results = !slots;
              }))
  else
    Certified
      (ok
         (P.compile ~snapshot_id:"operational-mixed-v1" ~base_day:0
            ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
            ~lognormal_outputs:(requests ()) ~normal_outputs:(requests ())
            ~output_mode:P.Stream
            ~limits:
              {
                max_instruments = !size;
                max_scenarios = Array.length offsets;
                max_calculations = calculations;
                tile_rows = !tile_rows;
                max_workers = !workers;
                max_buffered_results = !slots;
                max_groups = groups;
              }))

let describe = function
  | Fast p ->
      let e = F.explain p in
      ( e.plan_id,
        e.instruments * e.scenarios,
        e.calculations,
        e.tiles,
        e.buffered_results )
  | Certified p ->
      let e = P.explain p in
      ( e.plan_id,
        e.instruments * e.scenarios,
        e.calculations,
        e.tiles,
        e.buffered_results )

let stop = function
  | P.Complete -> "complete"
  | P.Cancelled -> "cancelled"
  | P.Sink_failure _ -> "sink_failure"
  | P.Worker_failure _ -> "worker_failure"

let certified_error = function
  | P.Post_expiry -> "post_expiry"
  | P.Scalar (Production.Invalid_input _) -> "invalid_input"
  | P.Scalar Production.Invalid_accuracy -> "invalid_accuracy"
  | P.Scalar (Production.Unsupported _) -> "unsupported"
  | P.Scalar Production.Numerical_failure -> "numerical_failure"
  | P.Scalar Production.Accuracy_exceeded -> "accuracy_exceeded"

let fast_error = function
  | F.Post_expiry -> "post_expiry"
  | F.Scalar (Batch.Fast.Invalid_input _) -> "invalid_input"
  | F.Scalar Batch.Fast.Numerical_failure -> "numerical_failure"

(* Hash one event at a time: storage stays bounded by one serialized event.
   Hashing is sink work, included only for the digest sink and replay checks. *)
let append digest event =
  digest :=
    Digest.BLAKE256.string
      (!digest ^ Marshal.to_string event [ Marshal.No_sharing ])

let execute plan worker_count hashing cancellation =
  let rows = ref 0
  and served = ref 0
  and summaries = ref 0
  and finished = ref 0 in
  let first = ref None and digest = ref "" and errors = Hashtbl.create 8 in
  let count_error name =
    Hashtbl.replace errors name
      (1 + Option.value (Hashtbl.find_opt errors name) ~default:0)
  in
  let row scenario instrument =
    if scenario <> !rows / !size || instrument <> !rows mod !size then
      failwith "non-prefix row order";
    if !first = None then first := Some (monotonic ());
    incr rows
  in
  let c =
    match plan with
    | Fast p ->
        F.execute p ~workers:worker_count ~cancellation ~sink:(fun event ->
            if hashing then append digest event;
            (match event with
            | F.Row r -> (
                row r.scenario_id r.instrument_index;
                match r.price with
                | Ok _ -> incr served
                | Error e -> count_error (fast_error e))
            | F.Finished _ -> incr finished);
            Ok ())
    | Certified p ->
        P.execute p ~workers:worker_count ~cancellation ~sink:(fun event ->
            if hashing then append digest event;
            (match event with
            | P.Row r ->
                row r.scenario_id r.instrument_index;
                List.iter
                  (fun (P.Outcome (_, r)) ->
                    match r with
                    | Ok _ -> incr served
                    | Error e -> count_error (certified_error e))
                  r.outcomes
            | P.Summary _ -> incr summaries
            | P.Finished _ -> incr finished);
            Ok ())
  in
  let failed = Hashtbl.fold (fun _ n sum -> n + sum) errors 0 in
  if
    !finished <> 1 || c.rows_committed <> !rows
    || c.calculations_committed <> !served + failed
  then failwith "completion accounting mismatch";
  if c.stop <> P.Complete && c.stop <> P.Cancelled then
    failwith "executor failed";
  let _, _, calculations, _, _ = describe plan in
  if c.stop = P.Complete && c.calculations_committed <> calculations then
    failwith "incomplete result marked complete";
  let errors =
    List.sort compare
      (Hashtbl.fold (fun name n xs -> (name, n) :: xs) errors [])
  in
  ( c,
    !served,
    errors,
    !summaries,
    !first,
    Digest.BLAKE256.to_hex (Digest.BLAKE256.string !digest) )

let run compiled cancel_ms =
  let before = monotonic () in
  let a0, b0, c0 = Gc.counters () in
  let gc0 = Gc.quick_stat () and cpu0 = Sys.time () in
  let plan = if !policy = "recompile" then make () else compiled in
  let after_compile = monotonic () in
  let cancellation = P.cancellation () in
  let done_ = Atomic.make false and cancelled_at = Atomic.make None in
  let controller =
    if cancel_ms < 0. then None
    else if cancel_ms = 0. then (
      Atomic.set cancelled_at (Some (monotonic ()));
      P.cancel cancellation;
      None)
    else
      Some
        (Domain.spawn (fun () ->
             let deadline = after_compile +. (cancel_ms /. 1000.) in
             let rec wait () =
               if not (Atomic.get done_) then
                 let remaining = deadline -. monotonic () in
                 if remaining <= 0. then (
                   Atomic.set cancelled_at (Some (monotonic ()));
                   P.cancel cancellation)
                 else (
                   Unix.sleepf (min remaining 0.001);
                   wait ())
             in
             wait ()))
  in
  let result, execution_end =
    Fun.protect
      ~finally:(fun () ->
        Atomic.set done_ true;
        Option.iter Domain.join controller)
      (fun () ->
        let r = execute plan !workers (!sink_mode = "digest") cancellation in
        (r, monotonic ()))
  in
  let after = monotonic () in
  let c, served, errors, summaries, first, digest = result in
  let a1, b1, c1 = Gc.counters () in
  let gc1 = Gc.quick_stat () in
  let json_time = function
    | None -> "null"
    | Some x -> Printf.sprintf "%.9g" x
  in
  let first_ms = Option.map (fun t -> (t -. before) *. 1000.) first in
  let cancellation_ms =
    match Atomic.get cancelled_at with
    | Some t when t <= execution_end -> Some ((execution_end -. t) *. 1000.)
    | _ -> None
  in
  let issued = Atomic.get cancelled_at in
  let issued_ms = Option.map (fun t -> (t -. before) *. 1000.) issued in
  let lateness_ms =
    Option.map
      (fun t -> max 0. (((t -. after_compile) *. 1000.) -. cancel_ms))
      issued
  in
  let errors_json =
    String.concat ","
      (List.map (fun (k, n) -> Printf.sprintf "%S:%d" k n) errors)
  in
  Printf.printf
    "{\"kind\":\"request\",\"stop\":%S,\"rows\":%d,\"calculations\":%d,\"served\":%d,\"errors\":{%s},\"summaries\":%d,\"request_ms\":%.9g,\"prepare_ms\":%.9g,\"execute_ms\":%.9g,\"cpu_ms\":%.9g,\"first_row_ms\":%s,\"cancel_observation_ms\":%s,\"cancel_issued_ms\":%s,\"cancel_schedule_lateness_ms\":%s,\"coordinator_bytes\":%.0f,\"minor_collections\":%d,\"major_collections\":%d,\"digest\":%s}\n\
     %!"
    (stop c.stop) c.rows_committed c.calculations_committed served errors_json
    summaries
    ((after -. before) *. 1000.)
    ((after_compile -. before) *. 1000.)
    ((execution_end -. after_compile) *. 1000.)
    ((Sys.time () -. cpu0) *. 1000.)
    (json_time first_ms)
    (json_time cancellation_ms)
    (json_time issued_ms) (json_time lateness_ms)
    (8. *. (a1 +. c1 -. b1 -. a0 -. c0 +. b0))
    (gc1.minor_collections - gc0.minor_collections)
    (gc1.major_collections - gc0.major_collections)
    (if !sink_mode = "digest" then Printf.sprintf "%S" digest else "null")

let () =
  Arg.parse
    [
      ("--size", Arg.Set_int size, "Position count");
      ("--days", Arg.Set_string days, "Comma-separated valuation day offsets");
      ("--tile-rows", Arg.Set_int tile_rows, "Rows per tile");
      ("--workers", Arg.Set_int workers, "Workers per request");
      ("--buffer-slots", Arg.Set_int slots, "Compiled result-slot limit");
      ( "--mode",
        Arg.Symbol ([ "fast"; "certified" ], fun s -> mode := s),
        "Pricing mode" );
      ( "--outputs",
        Arg.Symbol ([ "price"; "all" ], fun s -> outputs := s),
        "Certified output set" );
      ( "--policy",
        Arg.Symbol ([ "reuse"; "recompile" ], fun s -> policy := s),
        "Plan policy" );
      ( "--sink",
        Arg.Symbol ([ "count"; "digest" ], fun s -> sink_mode := s),
        "Sink work" );
      ( "--allowance",
        Arg.Set_float allowance,
        "Absolute certified output allowance" );
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "planner-load-v1";
            exit 0),
        "Version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Persistent planner operational probe";
  if
    !size < 1 || !workers < 1 || !tile_rows < 1 || !slots < 1
    || (!mode = "fast" && !outputs <> "price")
    || (not (Float.is_finite !allowance))
    || !allowance <= 0.
  then invalid_arg "invalid operational workload";
  let started = monotonic () in
  let compiled = make () in
  let plan_id, rows, calculations, tiles, bound = describe compiled in
  Printf.printf
    "{\"kind\":\"ready\",\"plan_id\":%S,\"rows\":%d,\"calculations\":%d,\"tiles\":%d,\"buffered_results\":%d,\"initial_compile_ms\":%.9g}\n\
     %!"
    plan_id rows calculations tiles bound
    ((monotonic () -. started) *. 1000.);
  let rec loop () =
    match input_line stdin with
    | "run" ->
        run compiled (-1.);
        loop ()
    | "check" ->
        let one = execute compiled 1 true (P.cancellation ()) in
        let many = execute compiled !workers true (P.cancellation ()) in
        let c, _, _, _, _, a = one and d, _, _, _, _, b = many in
        if c <> d || a <> b then failwith "worker replay mismatch";
        Printf.printf "{\"kind\":\"check\",\"digest\":%S}\n%!" a;
        loop ()
    | "quit" -> ()
    | line when String.starts_with ~prefix:"cancel " line ->
        let ms = float_of_string (String.sub line 7 (String.length line - 7)) in
        if (not (Float.is_finite ms)) || ms < 0. then invalid_arg "cancel delay";
        run compiled ms;
        loop ()
    | _ -> failwith "unknown probe command"
    | exception End_of_file -> ()
  in
  loop ()
