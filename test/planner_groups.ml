open Morphiq_risk
module P = Planner

let ok = function Ok x -> x | Error s -> failwith s
let check b message = if not b then failwith message
let sigma = Result.get_ok (Vol.lognormal 0.2)

let market =
  [|
    P.{ name = "S"; market = Spot_market { spot = 100.; volatility = sigma } };
    P.
      {
        name = "F";
        market = Forward_market { forward = 100.; volatility = sigma };
      };
  |]

let position id model rate_factor =
  P.
    {
      id;
      model;
      rate_factor;
      factor = (match model with Bsm _ -> "S" | _ -> "F");
      currency = "USD";
      quantity = 1.;
      strike = 95.;
      expiry_day = 365;
      rate = 0.;
      side = Side.Call;
    }

let compile portfolio outputs max_groups =
  P.compile ~snapshot_id:"group-limits-v1" ~base_day:0
    ~day_count:P.Actual_365_fixed ~portfolio ~market
    ~scenarios:(ok (Scenario.cartesian []))
    ~lognormal_outputs:outputs ~normal_outputs:[] ~output_mode:P.Aggregate_only
    ~limits:
      P.
        {
          max_instruments = 100;
          max_scenarios = 1;
          max_calculations = 1000;
          tile_rows = 2;
          max_workers = 2;
          max_buffered_results = 10;
          max_groups;
        }

let trace = Buffer.create 1024

let run plan =
  let summaries = ref [] in
  let status =
    P.execute plan ~workers:2 ~cancellation:(P.cancellation ())
      ~sink:(fun event ->
        Buffer.add_string trace (Marshal.to_string event []);
        (match event with
        | P.Summary s -> summaries := s :: !summaries
        | _ -> ());
        Ok ())
  in
  check (status.stop = P.Complete) "group execution failed";
  List.rev !summaries

let exercise label portfolio expected =
  (* Output names are group coordinates too, even within one position. *)
  List.iter
    (fun outputs ->
      let groups = expected * List.length outputs in
      for limit = 0 to groups + 1 do
        match compile portfolio outputs limit with
        | Error s ->
            check
              (limit < groups && s = "aggregation group limit exceeded")
              (label ^ ": wrong rejection")
        | Ok plan ->
            check (limit >= groups) (label ^ ": excess groups accepted");
            check ((P.explain plan).groups = groups) (label ^ ": wrong count");
            Buffer.add_string trace (P.manifest plan);
            let summaries = run plan in
            check (List.length summaries = groups) (label ^ ": summary count");
            check
              (List.for_all
                 (fun (s : P.summary) -> s.complete && s.failed = 0)
                 summaries)
              (label ^ ": incomplete total");
            let keys = List.map (fun (s : P.summary) -> s.bucket) summaries in
            check (keys = List.sort_uniq compare keys) (label ^ ": bucket order");
            if outputs <> [] then
              check
                (List.fold_left
                   (fun n (s : P.summary) -> n + s.successful)
                   0 summaries
                = Array.length portfolio * List.length outputs)
                (label ^ ": duplicate contributions lost")
      done)
    [
      [];
      [ P.Output (Production.Price, 1e-10) ];
      [ P.Output (Production.Price, 1e-10); P.Output (Production.Delta, 1e-10) ];
    ]

let () =
  exercise "empty" [||] 0;
  exercise "single" [| position "a" P.Black76 "z" |] 1;
  let duplicates =
    Array.init 12 (fun i -> position (string_of_int i) P.Black76 "z")
  in
  exercise "duplicates" duplicates 1;
  let mixed = Array.append duplicates [| position "new" P.Black76 "a" |] in
  exercise "new at end" mixed 2;
  exercise "new at start"
    (Array.init (Array.length mixed) (fun i ->
         mixed.(Array.length mixed - i - 1)))
    2;
  List.iter
    (fun (name, model) ->
      List.iter
        (fun zero ->
          let portfolio =
            [|
              position "a" (model zero) "z";
              position "b" (model (-.zero)) "z";
              position "c" (model 0.01) "z";
            |]
          in
          exercise name portfolio 2;
          let plan =
            ok
              (compile (Array.sub portfolio 0 2)
                 [ P.Output (Production.Price, 1e-10) ]
                 1)
          in
          let summaries = run plan in
          let representative =
            match (List.hd summaries).bucket.model with
            | P.Bsm b -> b.dividend_yield
            | P.Displaced d -> d
            | _ -> assert false
          in
          check
            (Int64.bits_of_float representative = Int64.bits_of_float zero)
            "equivalent-key representative changed")
        [ 0.; -0. ])
    [
      ("BSM signed zero", fun x -> P.Bsm { dividend_yield = x });
      ("displaced signed zero", fun x -> P.Displaced x);
    ];
  let plan =
    ok (compile duplicates [ P.Output (Production.Price, 1e-10) ] max_int)
  in
  check ((P.explain plan).groups = 1) "max_int group limit";
  Printf.printf
    "planner groups: limits, duplicates, signed zeros, ordered totals; replay=%s\n"
    (Digest.BLAKE256.to_hex (Digest.BLAKE256.string (Buffer.contents trace)))
