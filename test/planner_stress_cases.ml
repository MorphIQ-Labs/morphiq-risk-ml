open Morphiq_risk

module Make (P : Planner_signature.S) = struct
  let ok = function Ok x -> x | Error e -> failwith e
  let check b message = if not b then failwith message
  let vol = Result.get_ok (Vol.lognormal 0.2)
  let normal = Result.get_ok (Vol.normal 10.)

  let market =
    [|
      P.{ name = "s"; market = Spot_market { spot = 100.; volatility = vol } };
      P.
        {
          name = "f";
          market = Forward_market { forward = 100.; volatility = vol };
        };
      P.
        {
          name = "n";
          market = Normal_market { forward = -2.; volatility = normal };
        };
    |]

  let portfolio count =
    Array.init count (fun i ->
        P.
          {
            id = string_of_int i;
            factor = (match i mod 4 with 0 -> "s" | 3 -> "n" | _ -> "f");
            model =
              (match i mod 4 with
              | 0 -> Bsm { dividend_yield = 0.01 }
              | 1 -> Black76
              | 2 -> Displaced 120.
              | _ -> Bachelier);
            rate_factor = "r";
            currency = "USD";
            quantity = (match i mod 3 with 0 -> 1e8 | 1 -> -1e8 | _ -> 0.25);
            strike = (if i mod 4 = 3 then -1. else 100.);
            expiry_day =
              (match i mod 7 with 0 -> 365 | 1 -> 0 | 2 -> -1 | _ -> 90);
            rate = (if i mod 11 = 0 then 1024. else 0.02);
            side = (if i mod 2 = 0 then Side.Call else Side.Put);
          })

  let outputs : type c. bool -> c P.output list =
   fun empty ->
    if empty then []
    else
      [
        P.Output (Production.Price, 1e-10);
        P.Output (Production.Delta, 1e-10);
        P.Output (Production.Vega, Units.per_volatility 1e-10);
      ]

  let make ?(count = 17) ?(scenario_count = 3) ?(empty_outputs = false)
      ?(mode = P.Stream) ?limits tile_rows =
    let scenarios =
      ok
        (Scenario.paired
           (Array.init scenario_count (fun i ->
                Scenario.{ offset_days = i * 7; shocks = [] })))
    in
    let limits =
      Option.value limits
        ~default:
          P.
            {
              max_instruments = count;
              max_scenarios = scenario_count;
              max_calculations = count * scenario_count * 3;
              tile_rows;
              max_workers = 4;
              max_buffered_results = tile_rows * 4 * 3;
              max_groups = 12;
            }
    in
    P.compile ~snapshot_id:"planner-stress-v1" ~base_day:0
      ~day_count:P.Actual_365_fixed ~portfolio:(portfolio count) ~market
      ~scenarios ~lognormal_outputs:(outputs empty_outputs)
      ~normal_outputs:(outputs empty_outputs) ~output_mode:mode ~limits

  let run ?(workers = 1) ?(sink = fun _ -> Ok ()) plan =
    let events = ref [] in
    let completion =
      P.execute plan ~workers ~cancellation:(P.cancellation ())
        ~sink:(fun event ->
          events := event :: !events;
          sink event)
    in
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

  let verify count scenarios events completion =
    check (completion.P.stop = P.Complete) "incomplete stress run";
    check (completion.rows_committed = count * scenarios) "row accounting";
    let next = ref 0 and calculations = ref 0 and finished = ref 0 in
    let bounds = Hashtbl.create 64 in
    let positions = portfolio count in
    List.iter
      (function
        | P.Row row ->
            check
              ((row.scenario_id * count) + row.instrument_index = !next)
              "row order/coverage";
            check
              (row.instrument_id = string_of_int row.instrument_index)
              "stable row identity";
            incr next;
            List.iter
              (fun (P.Outcome (q, result)) ->
                incr calculations;
                let p = positions.(row.instrument_index) in
                let key = (row.scenario_id, p.factor, p.model, qname q) in
                let lo, hi, good, bad =
                  Option.value
                    (Hashtbl.find_opt bounds key)
                    ~default:(Q.zero, Q.zero, 0, 0)
                in
                let value =
                  match result with
                  | Error _ -> (lo, hi, good, bad + 1)
                  | Ok v ->
                      let w = Q.of_float p.quantity in
                      let centre = Q.mul w (Q.of_float (number q v.value)) in
                      let radius =
                        Q.mul (Q.abs w) (Q.of_float (number q v.absolute_error))
                      in
                      ( Q.add lo (Q.sub centre radius),
                        Q.add hi (Q.add centre radius),
                        good + 1,
                        bad )
                in
                Hashtbl.replace bounds key value)
              row.outcomes
        | P.Summary summary -> (
            check
              (!next = (summary.scenario_id + 1) * count)
              "premature summary";
            let key =
              ( summary.scenario_id,
                summary.bucket.factor,
                summary.bucket.model,
                summary.bucket.quantity_name )
            in
            let lo, hi, good, bad = Hashtbl.find bounds key in
            Hashtbl.remove bounds key;
            check
              (good = summary.successful && bad = summary.failed)
              "summary counts";
            check
              (summary.complete
              = (bad = 0 && Option.is_some summary.successful_subset))
              "summary completeness";
            match summary.successful_subset with
            | None -> failwith "stress aggregation unexpectedly unresolved"
            | Some total ->
                let v = Q.of_float total.value
                and e = Q.of_float total.absolute_error in
                check
                  (Q.compare (Q.sub v e) lo <= 0
                  && Q.compare (Q.add v e) hi >= 0)
                  "rational aggregate containment")
        | P.Finished c ->
            incr finished;
            check (c = completion) "terminal accounting")
      events;
    check
      (!next = count * scenarios
      && !calculations = completion.calculations_committed
      && !finished = 1
      && Hashtbl.length bounds = 0)
      "coverage/summary completion"
end
