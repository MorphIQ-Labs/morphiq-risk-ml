open Morphiq_risk
module P = Planner

external monotonic : unit -> float = "morphiq_bench_monotonic"

let ok = function Ok x -> x | Error _ -> failwith "benchmark admission"

let outputs : type c. unit -> c P.output list =
 fun () ->
  P.
    [
      Output (Production.Price, 1e-8);
      Output (Production.Delta, 1e-8);
      Output (Production.Gamma, 1e-8);
      Output (Production.Rho, 1e-8);
      Output (Production.Theta, Units.time_rate 1e-8);
      Output (Production.Vega, Units.per_volatility 1e-8);
      Output (Production.Vanna, Units.per_volatility 1e-8);
      Output (Production.Volga, Units.per_volatility_squared 1e-8);
      Output (Production.Charm, Units.time_rate 1e-8);
      Output (Production.Veta, Units.volatility_time_rate 1e-8);
      Output (Production.Color, Units.time_rate 1e-8);
    ]

let rec take n = function
  | [] -> []
  | _ when n = 0 -> []
  | x :: xs -> x :: take (n - 1) xs

let sample label f =
  for _ = 1 to 2 do
    f ()
  done;
  for round = 1 to 5 do
    Gc.full_major ();
    let a0, b0, c0 = Gc.counters () in
    let start = monotonic () and cpu = Sys.time () in
    for _ = 1 to 2 do
      f ()
    done;
    let elapsed = monotonic () -. start and cpu = Sys.time () -. cpu in
    let a1, b1, c1 = Gc.counters () in
    Printf.printf "TIME %s %d %.3f %.3f %.3f\n%!" label round
      (elapsed *. 1e9 /. 2.)
      (cpu *. 1e9 /. 2.)
      (8. *. (a1 +. c1 -. b1 -. a0 -. c0 +. b0) /. 2.)
  done

let () =
  if Array.length Sys.argv <> 1 then
    failwith "shared_portfolio takes no arguments";
  let models =
    P.[| Bsm { dividend_yield = 0.01 }; Black76; Displaced 120.; Bachelier |]
  in
  let names = [| "S"; "F"; "D"; "N" |] in
  let market =
    P.
      [|
        {
          name = "S";
          market =
            Spot_market { spot = 100.; volatility = ok (Vol.lognormal 0.2) };
        };
        {
          name = "F";
          market =
            Forward_market
              { forward = 100.; volatility = ok (Vol.lognormal 0.2) };
        };
        {
          name = "D";
          market =
            Forward_market
              { forward = -50.; volatility = ok (Vol.lognormal 0.2) };
        };
        {
          name = "N";
          market =
            Normal_market { forward = -2.; volatility = ok (Vol.normal 10.) };
        };
      |]
  in
  List.iter
    (fun regime ->
      let portfolio =
        Array.init 8 (fun i ->
            P.
              {
                id = string_of_int i;
                factor = names.(i / 2);
                rate_factor = "USD-flat";
                currency = "USD";
                quantity = (if i mod 2 = 0 then 100. else -99.);
                model = models.(i / 2);
                strike =
                  (if i / 2 = 2 then -40. else if i / 2 = 3 then -1. else 95.);
                expiry_day = 365;
                rate = (if regime = "failure" then -2000. else 0.02);
                side = (if i mod 2 = 0 then Side.Call else Put);
              })
      in
      let days =
        if regime = "boundaries" then [| 0; 365; 366 |] else [| 0; 7; 30 |]
      in
      let scenarios = ok (Scenario.cartesian [ Scenario.Time days ]) in
      List.iter
        (fun count ->
          let compile () =
            ok
              (P.compile ~snapshot_id:"shared-certification-v1" ~base_day:0
                 ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
                 ~lognormal_outputs:(take count (outputs ()))
                 ~normal_outputs:(take count (outputs ()))
                 ~output_mode:P.Stream
                 ~limits:
                   P.
                     {
                       max_instruments = 8;
                       max_scenarios = 3;
                       max_calculations = 264;
                       tile_rows = 4;
                       max_workers = 2;
                       max_buffered_results = 264;
                       max_groups = 44;
                     })
          in
          let plan = compile () in
          let execute ~workers ~sink p =
            P.execute p ~workers ~cancellation:(P.cancellation ()) ~sink
          in
          let trace workers p =
            let events = ref [] and served = ref 0 and failed = ref 0 in
            let status =
              execute ~workers
                ~sink:(fun event ->
                  events := event :: !events;
                  (match event with
                  | P.Row r ->
                      List.iter
                        (fun (P.Outcome (_, x)) ->
                          match x with
                          | Ok _ -> incr served
                          | Error _ -> incr failed)
                        r.outcomes
                  | _ -> ());
                  Ok ())
                p
            in
            if
              status.stop <> P.Complete
              || status.rows_committed <> 24
              || !served + !failed <> 24 * count
            then failwith "incomplete benchmark validation";
            let digest =
              Digest.BLAKE256.to_hex
                (Digest.BLAKE256.string
                   (Marshal.to_string
                      (List.rev !events, status)
                      [ Marshal.No_sharing ]))
            in
            (digest, !served, !failed)
          in
          let digest, served, failed = trace 1 plan in
          if
            trace 2 plan <> (digest, served, failed)
            || trace 1 (compile ()) <> (digest, served, failed)
          then failwith "worker/compile replay differs";
          let label = regime ^ "/" ^ string_of_int count in
          Printf.printf "CHECK %s %s %d %d\n%!" label digest served failed;
          sample (label ^ "/compile") (fun () ->
              ignore (Sys.opaque_identity (compile ())));
          sample (label ^ "/execution") (fun () ->
              ignore
                (Sys.opaque_identity
                   (execute ~workers:1 ~sink:(fun _ -> Ok ()) plan)));
          sample (label ^ "/end-to-end") (fun () ->
              ignore
                (Sys.opaque_identity
                   (execute ~workers:1 ~sink:(fun _ -> Ok ()) (compile ())))))
        [ 1; 2; 11 ])
    [ "ordinary"; "boundaries"; "failure" ]
