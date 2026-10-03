open Morphiq_risk
module P = Planner

let ok = function Ok x -> x | Error _ -> failwith "unexpected rejection"

let outputs : type c. unit -> c P.output list =
 fun () ->
  [
    P.Output (Production.Price, 1e-10);
    P.Output (Production.Delta, 1e-10);
    P.Output (Production.Gamma, 1e-10);
    P.Output (Production.Rho, 1e-10);
    P.Output (Production.Theta, Units.time_rate 1e-10);
    P.Output (Production.Vega, Units.per_volatility 1e-10);
    P.Output (Production.Vanna, Units.per_volatility 1e-10);
    P.Output (Production.Volga, Units.per_volatility_squared 1e-10);
    P.Output (Production.Charm, Units.time_rate 1e-10);
    P.Output (Production.Veta, Units.volatility_time_rate 1e-10);
    P.Output (Production.Color, Units.time_rate 1e-10);
  ]

let name : type c a. (c, a) Production.quantity -> string = function
  | Price -> "price"
  | Delta -> "delta"
  | Gamma -> "gamma"
  | Rho -> "rho"
  | Theta -> "theta"
  | Vega -> "vega"
  | Vanna -> "vanna"
  | Volga -> "volga"
  | Charm -> "charm"
  | Veta -> "veta"
  | Color -> "color"

let number : type c a. (c, a) Production.quantity -> a -> float =
 fun q x ->
  match q with
  | Price -> x
  | Delta -> x
  | Gamma -> x
  | Rho -> x
  | Theta -> (x :> float)
  | Vega -> (x :> float)
  | Vanna -> (x :> float)
  | Volga -> (x :> float)
  | Charm -> (x :> float)
  | Veta -> (x :> float)
  | Color -> (x :> float)

let () =
  let workers = ref 1 in
  Arg.parse
    [
      ("--workers", Arg.Set_int workers, "worker count");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "planner-reference-v1";
            exit 0),
        "version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "planner_reference";
  let models =
    [|
      P.Bsm { dividend_yield = 0.01 }; P.Black76; P.Displaced 120.; P.Bachelier;
    |]
  in
  let factors = [| "S"; "F"; "D"; "N" |] in
  let portfolio =
    Array.init 8 (fun i ->
        P.
          {
            id = string_of_int i;
            factor = factors.(i / 2);
            rate_factor = "USD-flat";
            currency = "USD";
            quantity = 1.;
            model = models.(i / 2);
            strike =
              (if i / 2 = 2 then -40. else if i / 2 = 3 then -1. else 100.);
            expiry_day = 90;
            rate = 0.02;
            side = (if i mod 2 = 0 then Side.Call else Put);
          })
  in
  let market =
    [|
      P.
        {
          name = "S";
          market =
            Spot_market { spot = 100.; volatility = ok (Vol.lognormal 0.2) };
        };
      P.
        {
          name = "F";
          market =
            Forward_market
              { forward = 100.; volatility = ok (Vol.lognormal 0.2) };
        };
      P.
        {
          name = "D";
          market =
            Forward_market
              { forward = -50.; volatility = ok (Vol.lognormal 0.2) };
        };
      P.
        {
          name = "N";
          market =
            Normal_market { forward = -2.; volatility = ok (Vol.normal 10.) };
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
               factor = "S";
               field = Spot;
               mode = Relative;
               range = ok (Scenario.levels [| 0.9; 1.; 1.1 |]);
             };
           Scenario.Market
             {
               factor = "F";
               field = Lognormal_volatility;
               mode = Absolute;
               range = ok (Scenario.levels [| 0.1; 0.2; 0.4 |]);
             };
         ])
  in
  let plan =
    ok
      (P.compile ~snapshot_id:"arb-planner-reference-v1" ~base_day:0
         ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
         ~lognormal_outputs:(outputs ()) ~normal_outputs:(outputs ())
         ~output_mode:P.Stream
         ~limits:
           P.
             {
               max_instruments = 8;
               max_scenarios = 27;
               max_calculations = 2376;
               tile_rows = 3;
               max_workers = 4;
               max_buffered_results = 132;
               max_groups = 44;
             })
  in
  let result =
    P.execute plan ~workers:!workers ~cancellation:(P.cancellation ())
      ~sink:(fun event ->
        (match event with
        | P.Row row ->
            let i = row.instrument_index and s = row.scenario_id in
            let model =
              [| "bsm"; "black76"; "displaced"; "bachelier" |].(i / 2)
            in
            let spot =
              match i / 2 with
              | 0 -> 100. *. [| 0.9; 1.; 1.1 |].(s / 3 mod 3)
              | 1 -> 100.
              | 2 -> -50.
              | _ -> -2.
            in
            let sigma =
              if i / 2 = 1 then [| 0.1; 0.2; 0.4 |].(s mod 3)
              else if i / 2 = 3 then 10.
              else 0.2
            in
            let inputs =
              [
                spot;
                portfolio.(i).strike;
                float_of_int (90 - [| 0; 7; 30 |].(s / 9)) /. 365.;
                0.02;
                (if i / 2 = 0 then 0.01 else 0.02);
                sigma;
                (if i / 2 = 2 then 120. else 0.);
              ]
            in
            List.iter
              (fun (P.Outcome (q, r)) ->
                match r with
                | Error _ -> failwith "reference row not served"
                | Ok v ->
                    Printf.printf "%d %d %s %s %s" s i model
                      (if i mod 2 = 0 then "call" else "put")
                      (name q);
                    List.iter
                      (fun f -> Printf.printf " %016Lx" (Int64.bits_of_float f))
                      (inputs @ [ number q v.value; number q v.absolute_error ]);
                    print_newline ())
              row.outcomes
        | _ -> ());
        Ok ())
  in
  if result.stop <> P.Complete || result.calculations_committed <> 2376 then
    failwith "incomplete reference execution"
