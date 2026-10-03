open Morphiq_risk
module P = Planner
module S = Scenario

let ok = function Ok x -> x | Error _ -> failwith "unexpected rejection"
let check b s = if not b then failwith s
let reject r s = check (Result.is_error r) s
let logvol = ok (Vol.lognormal 0.2)
let normalvol = ok (Vol.normal 10.)

let limits =
  P.
    {
      max_instruments = 100;
      max_scenarios = 100;
      max_calculations = 10000;
      tile_rows = 2;
      max_workers = 4;
      max_buffered_results = 100;
      max_groups = 100;
    }

let market =
  [|
    P.{ name = "S"; market = Spot_market { spot = 100.; volatility = logvol } };
    P.
      {
        name = "F";
        market = Forward_market { forward = 100.; volatility = logvol };
      };
    P.
      {
        name = "N";
        market = Normal_market { forward = -2.; volatility = normalvol };
      };
  |]

let position id factor model quantity =
  P.
    {
      id;
      factor;
      model;
      quantity;
      rate_factor = "USD-flat";
      currency = "USD";
      strike = 100.;
      expiry_day = 90;
      rate = 0.02;
      side = Side.Call;
    }

let portfolio =
  [|
    position "a" "S" (P.Bsm { dividend_yield = 0.01 }) 1e12;
    position "b" "S" (P.Bsm { dividend_yield = 0.01 }) (-1e12);
    position "c" "F" P.Black76 3.;
    position "d" "F" (P.Displaced 120.) (-4.);
    { (position "e" "N" P.Bachelier 7.) with strike = -1. };
  |]

let outputs : type c. unit -> c P.output list =
 fun () ->
  [
    P.Output (Production.Price, 1e-10);
    P.Output (Production.Delta, 1e-10);
    P.Output (Production.Vega, Units.per_volatility 1e-10);
  ]

let scenarios =
  ok
    (S.cartesian
       [
         S.Time [| 0; 7; 90; 91 |];
         S.Market
           {
             factor = "S";
             field = Spot;
             mode = Relative;
             range = ok (S.levels [| 1.; 0. |]);
           };
       ])

let compile ?(portfolio = portfolio) ?(market = market) ?(scenarios = scenarios)
    ?(limits = limits) ?(output_mode = P.Stream) () =
  P.compile ~snapshot_id:"test-snapshot" ~base_day:0
    ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
    ~lognormal_outputs:(outputs ()) ~normal_outputs:(outputs ()) ~output_mode
    ~limits

let run ?(workers = 1) t =
  let events = ref [] in
  let completion =
    P.execute t ~workers ~cancellation:(P.cancellation ()) ~sink:(fun e ->
        events := e :: !events;
        Ok ())
  in
  check (completion.stop = P.Complete) "execution failed";
  (List.rev !events, completion)

let number : type c a. (c, a) Production.quantity -> a -> float =
 fun q x ->
  match q with
  | Price -> x
  | Delta -> x
  | Gamma -> x
  | Rho -> x
  | Theta -> (x :> float)
  | Charm -> (x :> float)
  | Color -> (x :> float)
  | Vega -> (x :> float)
  | Vanna -> (x :> float)
  | Volga -> (x :> float)
  | Veta -> (x :> float)

let qname : type c a. (c, a) Production.quantity -> string = function
  | Price -> "price"
  | Delta -> "delta"
  | Gamma -> "gamma"
  | Rho -> "rho"
  | Theta -> "theta/day"
  | Charm -> "charm/day"
  | Color -> "color/day"
  | Vega -> "vega/unit-vol"
  | Vanna -> "vanna/unit-vol"
  | Volga -> "volga/unit-vol^2"
  | Veta -> "veta/day/unit-vol"

let verify_sums events =
  let bounds = Hashtbl.create 20 in
  List.iter
    (function
      | P.Row r ->
          List.iter
            (fun (P.Outcome (q, value)) ->
              let p = portfolio.(r.instrument_index) in
              let key =
                (r.scenario_id, p.currency, p.factor, p.model, qname q)
              in
              let lo, hi, success, failed =
                Option.value
                  (Hashtbl.find_opt bounds key)
                  ~default:(Q.zero, Q.zero, 0, 0)
              in
              let b =
                match value with
                | Error _ -> (lo, hi, success, failed + 1)
                | Ok v ->
                    let x = Q.of_float (number q v.value)
                    and e = Q.of_float (number q v.absolute_error)
                    and w = Q.of_float p.quantity in
                    let centre = Q.mul w x and radius = Q.mul (Q.abs w) e in
                    ( Q.add lo (Q.sub centre radius),
                      Q.add hi (Q.add centre radius),
                      success + 1,
                      failed )
              in
              Hashtbl.replace bounds key b)
            r.outcomes
      | Summary s -> (
          let k = s.bucket in
          let lo, hi, success, failed =
            Hashtbl.find bounds
              (s.scenario_id, k.currency, k.factor, k.model, k.quantity_name)
          in
          check (success = s.successful && failed = s.failed) "summary counts";
          check
            (s.complete = (failed = 0 && Option.is_some s.successful_subset))
            "summary completeness";
          match s.successful_subset with
          | None -> failwith "ordinary sum unresolved"
          | Some total ->
              let v = Q.of_float total.value
              and e = Q.of_float total.absolute_error in
              check
                (Q.compare (Q.sub v e) lo <= 0 && Q.compare (Q.add v e) hi >= 0)
                "aggregate does not enclose exact rational sum")
      | Finished _ -> ())
    events

let () =
  let linear = ok (S.linear ~first:0.1 ~step:0.2 ~count:4) in
  check (S.range_value linear 3 = Float.fma 3. 0.2 0.1) "indexed FMA";
  check
    (Int64.bits_of_float
       (S.range_value (ok (S.linear ~first:(-0.) ~step:0. ~count:1)) 0)
    = Int64.min_int)
    "base signed zero";
  reject
    (S.linear ~first:Float.max_float ~step:Float.max_float ~count:2)
    "overflow range";
  reject (S.linear ~first:0. ~step:1. ~count:(-1)) "negative range";
  let levels = [| 1.; 2. |] in
  let r = ok (S.levels levels) in
  levels.(0) <- 99.;
  check (S.range_value r 0 = 1.) "range alias";
  let days = [| 0; 7 |] in
  let s =
    ok
      (S.cartesian
         [
           S.Time days;
           S.Market { factor = "S"; field = Spot; mode = Absolute; range = r };
         ])
  in
  days.(0) <- 100;
  check
    ((S.point s 0).offset_days = 0 && (S.point s 2).offset_days = 7)
    "Cartesian order/alias";
  check
    (S.count (ok (S.cartesian [])) = 1
    && S.count (ok (S.cartesian [ S.Time [||] ])) = 0)
    "empty axes";
  reject (S.cartesian [ S.Time [| 0 |]; S.Time [| 1 |] ]) "duplicate time";
  reject (S.paired [| { offset_days = -1; shocks = [] } |]) "backward roll";
  let huge = ok (S.linear ~first:0. ~step:0. ~count:1000000000) in
  reject
    (S.cartesian
       (List.init 3 (fun i ->
            S.Market
              {
                factor = string_of_int i;
                field = Spot;
                mode = Absolute;
                range = huge;
              })))
    "count overflow";
  let points = [| S.{ offset_days = 0; shocks = [] } |] in
  let paired = ok (S.paired points) in
  points.(0) <- S.{ offset_days = 5; shocks = [] };
  check ((S.point paired 0).offset_days = 0) "paired alias";
  let plan = ok (compile ()) in
  let ex = P.explain plan in
  check
    (ex.snapshot_id = "test-snapshot"
    && List.length ex.kernels = 4
    && ex.limits = limits)
    "inspectable dependencies and kernels";
  check
    (ex.instruments = 5 && ex.scenarios = 8 && ex.calculations = 120
   && ex.tiles = 24)
    "plan counts";
  let sequential, c = run plan in
  check (c.rows_committed = 40 && c.calculations_committed = 120) "coverage";
  verify_sums sequential;
  List.iter
    (function
      | P.Row r when r.scenario_id >= 6 ->
          List.iter
            (fun (P.Outcome (_, result)) ->
              check
                (match result with Error P.Post_expiry -> true | _ -> false)
                "post-expiry contract")
            r.outcomes
      | _ -> ())
    sequential;
  List.iter
    (fun workers ->
      let events, _ = run ~workers plan in
      check (events = sequential) "parallel replay")
    [ 2; 3; 4 ];
  let delayed = ref [] and coordinator = Domain.self () in
  let delayed_status =
    P.execute plan ~workers:4 ~cancellation:(P.cancellation ()) ~sink:(fun e ->
        check (Domain.self () = coordinator) "sink escaped coordinator";
        (* Simulate a consumer that cannot immediately accept the next row. *)
        Unix.sleepf 0.001;
        delayed := e :: !delayed;
        Ok ())
  in
  check
    (List.rev !delayed = sequential && delayed_status = c)
    "slow sink changed replay or completion";
  let differently_tiled =
    ok (compile ~limits:{ limits with tile_rows = 3 } ())
  in
  check
    (fst (run ~workers:3 differently_tiled) = sequential)
    "tile-size changes reduction";
  let seen = Hashtbl.create 40 in
  List.iter
    (function
      | P.Row r ->
          let key = (r.scenario_id, r.instrument_index) in
          check (not (Hashtbl.mem seen key)) "duplicate cell";
          Hashtbl.add seen key ()
      | _ -> ())
    sequential;
  check (Hashtbl.length seen = 40) "missing cells";
  let copied = Array.copy portfolio and copied_market = Array.copy market in
  let frozen = ok (compile ~portfolio:copied ~market:copied_market ()) in
  copied.(0) <- position "changed" "S" P.Black76 0.;
  copied_market.(0) <- market.(1);
  check (fst (run frozen) = sequential) "snapshot isolation";
  reject
    (compile ~portfolio:[| portfolio.(0); portfolio.(0) |] ())
    "duplicate ID";
  reject
    (compile ~limits:{ limits with max_calculations = 119 } ())
    "work limit";
  reject
    (compile ~limits:{ limits with max_buffered_results = 1 } ())
    "buffer limit";
  reject (compile ~limits:{ limits with max_groups = 1 } ()) "group limit";
  reject
    (compile ~portfolio:[| { (portfolio.(0)) with factor = "N" } |] ())
    "model binding";
  let wrong =
    ok
      (S.cartesian
         [
           S.Market
             {
               factor = "N";
               field = Lognormal_volatility;
               mode = Absolute;
               range = r;
             };
         ])
  in
  reject (compile ~scenarios:wrong ()) "shock coordinate";
  let other = ok (compile ~portfolio:[| portfolio.(0) |] ()) in
  reject (P.evaluate_tile other (P.tile plan 0)) "foreign tile";
  let separated =
    ok
      (compile
         ~portfolio:
           [|
             portfolio.(0);
             { (portfolio.(1)) with rate_factor = "different-rate" };
           |]
         ())
  in
  check ((P.explain separated).groups = 6) "rate-factor aggregation separation";
  reject
    (compile ~portfolio:[| { (portfolio.(0)) with rate_factor = "" } |] ())
    "missing rate factor";
  reject
    (compile
       ~portfolio:[| portfolio.(0); { (portfolio.(1)) with currency = "EUR" } |]
       ())
    "factor denomination mismatch";
  let empty = ok (compile ~portfolio:[||] ()) in
  check ((snd (run empty)).rows_committed = 0) "empty portfolio";
  let empty = ok (compile ~scenarios:(ok (S.paired [||])) ()) in
  check ((snd (run empty)).rows_committed = 0) "empty scenarios";
  let cancel = P.cancellation () in
  P.cancel cancel;
  let status =
    P.execute plan ~workers:2 ~cancellation:cancel ~sink:(fun _ -> Ok ())
  in
  check (status.stop = P.Cancelled && status.rows_committed = 0) "pre-cancel";
  let cancel = P.cancellation () in
  let delivered = ref 0 in
  let status =
    P.execute plan ~workers:3 ~cancellation:cancel ~sink:(fun e ->
        (match e with
        | P.Row _ ->
            incr delivered;
            P.cancel cancel
        | _ -> ());
        Ok ())
  in
  check
    (status.stop = P.Cancelled && status.rows_committed = 1 && !delivered = 1)
    "mid-wave cancellation";
  let events = ref 0 in
  let status =
    P.execute plan ~workers:2 ~cancellation:(P.cancellation ()) ~sink:(fun _ ->
        incr events;
        Error "closed")
  in
  check
    (status.stop = P.Sink_failure "closed"
    && status.rows_committed = 0 && !events = 1)
    "sink backpressure/failure";
  let status =
    P.execute plan ~workers:2 ~cancellation:(P.cancellation ()) ~sink:(fun _ ->
        failwith "sink exception")
  in
  check
    (match status.stop with Sink_failure _ -> true | _ -> false)
    "sink exception";
  let aggregate = ok (compile ~output_mode:P.Aggregate_only ()) in
  let events, _ = run ~workers:4 aggregate in
  check
    (List.filter (function P.Summary _ -> true | _ -> false) events
    = List.filter (function P.Summary _ -> true | _ -> false) sequential)
    "aggregate-only totals";
  check
    (List.for_all
       (function
         | P.Row r ->
             List.exists
               (fun (P.Outcome (_, x)) -> Result.is_error x)
               r.outcomes
         | _ -> true)
       events)
    "aggregate-only row policy";
  let inputs =
    Black.Bsm_carry.
      {
        spot = 100.;
        strike = 100.;
        time_to_expiry = 90. /. 365.;
        rate = 0.02;
        dividend_yield = 0.01;
      }
  in
  let request =
    Batch.Request
      ( Batch.Bsm,
        inputs,
        Side.Call,
        Batch.Evaluate (logvol, Production.Price, 1e-10) )
  in
  let scalar =
    Production.Bsm.evaluate
      (ok (Production.Bsm.admit inputs))
      Side.Call logvol Production.Price ~max_error:1e-10
  in
  check (Batch.run [| request; request |] = [| scalar; scalar |]) "batch/scalar";
  check (Batch.run [||] = [||]) "empty batch";
  let admitted = ok (Production.Bsm.admit inputs) in
  List.iter
    (fun quote ->
      check
        (Marshal.to_string
           (Batch.evaluate
              (Batch.Request (Batch.Bsm, inputs, Side.Call, Batch.Implied quote)))
           []
        = Marshal.to_string (Production.Bsm.implied admitted Side.Call quote) []
        )
        "batch IV class")
    [ -1.; 0.; 10.; 100.; nan ];
  (* Base-case request inputs must recover the exact scalar path. *)
  (match List.hd sequential with
  | P.Row { outcomes = P.Outcome (Production.Price, x) :: _; _ } ->
      check
        (x = Result.map_error (fun e -> P.Scalar e) scalar)
        "base case scalar recovery"
  | _ -> failwith "first row");
  Printf.printf
    "planner: exact scalar/batch, rational aggregate enclosures, scenario \
     coverage, isolation, failures and 1/2/3/4-worker replay passed\n"
