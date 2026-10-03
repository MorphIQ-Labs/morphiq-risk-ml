open Morphiq_risk

let ok = function Ok x -> x | Error _ -> failwith "request rejected"

let () =
  let workers = ref 2 in
  Arg.parse
    [
      ("--workers", Arg.Set_int workers, "number of workers (1-4)");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline Morphiq_risk.version;
            exit 0),
        "library version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "scenario_job [--workers N]";
  let module P = Planner in
  let market =
    [|
      P.
        {
          name = "ACME-USD";
          market =
            Spot_market { spot = 100.; volatility = ok (Vol.lognormal 0.2) };
        };
    |]
  in
  let portfolio =
    [|
      P.
        {
          id = "call-100";
          factor = "ACME-USD";
          rate_factor = "USD-flat";
          currency = "USD";
          quantity = 1000.;
          model = Bsm { dividend_yield = 0.01 };
          strike = 100.;
          expiry_day = 90;
          rate = 0.02;
          side = Side.Call;
        };
    |]
  in
  let scenarios =
    ok
      (Scenario.cartesian
         [
           Scenario.Time [| 0; 7; 30 |];
           Scenario.Market
             {
               factor = "ACME-USD";
               field = Spot;
               mode = Absolute;
               range = ok (Scenario.levels [| 90.; 100.; 110. |]);
             };
         ])
  in
  let plan =
    ok
      (P.compile ~snapshot_id:"example-frozen-market" ~base_day:0
         ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
         ~lognormal_outputs:[ P.Output (Production.Price, 1e-10) ]
         ~normal_outputs:[] ~output_mode:P.Aggregate_only
         ~limits:
           P.
             {
               max_instruments = 1;
               max_scenarios = 9;
               max_calculations = 9;
               tile_rows = 1;
               max_workers = 4;
               max_buffered_results = 4;
               max_groups = 1;
             })
  in
  let explanation = P.explain plan in
  Printf.printf
    "%d instruments x %d scenarios; %d calculations; at most %d buffered results\n\
     plan %s\n"
    explanation.instruments explanation.scenarios explanation.calculations
    explanation.buffered_results explanation.plan_id;
  let result =
    P.execute plan ~workers:!workers ~cancellation:(P.cancellation ())
      ~sink:(fun event ->
        (match event with
        | Summary s -> (
            match s.successful_subset with
            | Some total when s.complete ->
                Printf.printf "scenario %d: %.12g %s, numerical error <= %.4g\n"
                  s.scenario_id total.value s.bucket.currency
                  total.absolute_error
            | _ ->
                Printf.printf "scenario %d: incomplete valuation\n"
                  s.scenario_id)
        | Row row ->
            Printf.printf
              "scenario %d, instrument %s: refused calculation retained\n"
              row.scenario_id row.instrument_id
        | Finished c ->
            Printf.printf "committed %d rows; complete=%b\n" c.rows_committed
              (c.stop = P.Complete));
        Ok ())
  in
  if result.stop <> P.Complete then exit 1
