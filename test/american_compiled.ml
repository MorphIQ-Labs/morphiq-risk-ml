open Morphiq_risk
module A = Early_exercise.Bsm
module B = Batch.American
module P = Planner.American

let ok = function Ok x -> x | Error _ -> failwith "unexpected refusal"
let expect label p = if not p then failwith label

let same a b =
  Marshal.to_string a [ Marshal.No_sharing ]
  = Marshal.to_string b [ Marshal.No_sharing ]

let vol x = ok (Vol.lognormal x)

let cfg =
  ok
    (A.configure ~tolerance:10. ~space_cells:16 ~time_steps:16
       ~domain_expansions:2
       ~limits:
         A.
           {
             max_nodes = 1024;
             max_steps = 131072;
             max_policy_solves = 1048576;
             max_row_visits = 100000000;
             max_workspace_bytes = 8388608;
             policy_iterations = 64;
           })

let price = B.Price { pricing = cfg; premium = false; exercise_regions = false }

let greek_cfg =
  ok
    (A.configure_greeks
       [
         ok (A.request_greek ~tolerance:10. Delta);
         ok (A.request_greek ~tolerance:10. Gamma);
       ])

let inputs =
  A.
    {
      spot = 100.;
      strike = 90.;
      rate = 0.05;
      dividend_yield = 0.;
      time_to_expiry = 1.;
      opens_at = 0.;
      volatility = vol 0.2;
    }

let admitted = ok (A.admit inputs)

let inverse =
  ok
    (A.Implied_volatility.configure ~pricing:cfg ~lower:(vol 0.05)
       ~upper:(vol 0.6) ~width:0.01 ~max_evaluations:32)

let quote =
  ok (A.Implied_volatility.quote (ok (A.price cfg admitted Side.Call)).value)

let certificate = ok (A.Certified.absolute_error_limit 1e-9)

let outputs =
  B.
    [
      Output price;
      Output (Greeks (cfg, greek_cfg));
      Output (Implied (inverse, quote));
      Output (Certified_price certificate);
    ]

let batch_limits =
  B.
    {
      max_requests = 20;
      max_outputs = 80;
      max_solver_workspace_bytes = 8388608;
    }

let scalar_model = B.Constant admitted

let batch () =
  let a =
    [|
      B.Request { id = "call"; model = scalar_model; side = Side.Call; outputs };
    |]
  in
  let plan = ok (B.compile ~limits:batch_limits a) in
  let expected = B.evaluate a.(0) in
  let result = B.execute plan in
  expect "compiled batch complete scalar equivalence"
    (same result [| expected |]);
  a.(0) <-
    B.Request
      { id = "changed"; model = scalar_model; side = Side.Put; outputs = [] };
  result.(0) <- { id = "mutated"; outcomes = [] };
  expect "batch owns arrays" (same (B.execute plan) [| expected |]);
  let worker = Domain.spawn (fun () -> B.execute plan) in
  expect "concurrent immutable batch"
    (same (B.execute plan) (Domain.join worker));
  expect "batch empty" (B.length (ok (B.compile ~limits:batch_limits [||])) = 0);
  expect "batch request cap"
    (Result.is_error
       (B.compile ~limits:{ batch_limits with max_requests = 0 } a));
  let r =
    B.Request
      {
        id = "x";
        model = scalar_model;
        side = Side.Put;
        outputs = [ B.Output price ];
      }
  in
  expect "batch output cap"
    (Result.is_error
       (B.compile ~limits:{ batch_limits with max_outputs = 0 } [| r |]));
  expect "batch workspace cap"
    (Result.is_error
       (B.compile
          ~limits:{ batch_limits with max_solver_workspace_bytes = 0 }
          [| r |]));
  expect "batch unique IDs"
    (Result.is_error (B.compile ~limits:batch_limits [| r; r |]));
  let calls = ref 0 in
  let cancelled =
    B.evaluate
      ~cancel:(fun () ->
        incr calls;
        !calls = 32)
      r
  in
  expect "batch forwards in-solve cancellation"
    (match cancelled.outcomes with
    | [ B.Outcome (B.Price _, Error (B.Pricing A.Cancelled)) ] -> !calls = 32
    | _ -> false);
  let raised =
    try
      ignore (B.evaluate ~cancel:(fun () -> raise Exit) r);
      false
    with Exit -> true
  in
  expect "batch callback exception" raised;
  expect "batch mixed assurance outcomes"
    (match expected.outcomes with
    | [
     B.Outcome (B.Price _, Ok p);
     B.Outcome (B.Greeks _, Ok g);
     B.Outcome (B.Implied _, Ok i);
     B.Outcome (B.Certified_price _, Ok c);
    ] ->
        p.assurance = A.Estimated_only
        && g.price.assurance = A.Estimated_only
        && i.assurance = A.Estimated_only
        && abs_float (p.value -. c.value) <= 1e-8
    | _ -> false)

let limits =
  P.
    {
      max_instruments = 64;
      max_market_factors = 64;
      max_scenarios = 64;
      max_calculations = 1024;
      tile_rows = 2;
      max_workers = 3;
      max_buffered_results = 24;
      max_solver_workspace_bytes = 8388608;
      max_schedule_events = 64;
    }

let market = P.[| { name = "S"; spot = 100. } |]

let constant =
  P.Constant { rate = 0.05; dividend_yield = 0.; volatility = vol 0.2 }

let position ?(id = "p") ?(side = Side.Call) ?(cash = None)
    ?(exercise =
      P.American
        { opening = { day = 0; side = A.Regular }; expiry_side = A.Regular })
    ?(expiry_day = 365) ?(strike = 90.) model outputs =
  P.Position
    {
      id;
      factor = "S";
      currency = "USD";
      quantity = -3.;
      strike;
      expiry_day;
      side;
      model;
      exercise;
      cash;
      outputs;
    }

let point ?(shocks = []) d = Scenario.{ offset_days = d; shocks }

let compile ?(limits = limits) ?(day_count = Planner.Actual_365_fixed)
    ?(cash_at_valuation = P.Before_payment) ?(market = market)
    ?(snapshot_id = "test") portfolio points =
  P.compile ~snapshot_id ~base_day:0 ~day_count ~cash_at_valuation ~portfolio
    ~market
    ~scenarios:(ok (Scenario.paired points))
    ~limits

let rows t =
  List.init (P.explain t).tiles (fun i ->
      Array.to_list (ok (P.evaluate_tile t (P.tile t i))))
  |> List.flatten

let run ?(workers = 1) ?cancel_at ?fail_at ?(throws = false) plan =
  let c = Planner.cancellation ()
  and emitted = ref []
  and finished = ref None in
  let completion =
    P.execute plan ~workers ~cancellation:c ~sink:(function
      | P.Row r ->
          if fail_at = Some (List.length !emitted) then
            if throws then raise Exit else Error "sink"
          else (
            emitted := r :: !emitted;
            if cancel_at = Some (List.length !emitted) then Planner.cancel c;
            Ok ())
      | P.Finished x ->
          finished := Some x;
          Ok ())
  in
  (completion, List.rev !emitted, !finished)

let single_price row : A.estimated_price =
  match row.P.outcomes with
  | P.Outcome (B.Price _, Ok x) :: _ -> x
  | _ -> failwith "price required"

let constant_dates () =
  let portfolio =
    [|
      position constant outputs;
      position ~id:"put" ~side:Side.Put constant [ B.Output price ];
    |]
  in
  let points =
    [|
      point 0;
      point 30;
      point 365;
      point 366;
      point
        ~shocks:
          [ Scenario.{ factor = "S"; field = Spot; adjustment = Replace 0. } ]
        0;
      point
        ~shocks:
          [
            Scenario.
              {
                factor = "S";
                field = Lognormal_volatility;
                adjustment = Replace (-1.);
              };
          ]
        0;
    |]
  in
  let p = ok (compile portfolio points) in
  let rs = rows p in
  List.iter
    (fun r ->
      if r.P.scenario_id = 3 then
        expect "post expiry per output"
          (List.for_all
             (function
               | P.Outcome (_, Error P.Post_expiry) -> true | _ -> false)
             r.outcomes)
      else if r.scenario_id = 5 then
        expect "invalid volatility per output"
          (List.for_all
             (function
               | P.Outcome (_, Error (P.Volatility _)) -> true | _ -> false)
             r.outcomes)
      else
        let days =
          if r.scenario_id = 1 then 335
          else if r.scenario_id = 2 then 0
          else 365
        in
        let spot = if r.scenario_id = 4 then 0. else 100. in
        let a =
          ok (A.admit { inputs with spot; time_to_expiry = float days /. 365. })
        in
        let (B.Request request) =
          if r.instrument_index = 0 then
            B.Request
              { id = "p"; model = B.Constant a; side = Side.Call; outputs }
          else
            B.Request
              {
                id = "put";
                model = B.Constant a;
                side = Side.Put;
                outputs = [ B.Output price ];
              }
        in
        let e = B.evaluate (B.Request request) in
        let e =
          List.map
            (fun (B.Outcome (op, result)) ->
              P.Outcome (op, Result.map_error (fun e -> P.Scalar e) result))
            e.outcomes
        in
        expect "dated scalar complete equivalence" (same r.outcomes e))
    rs;
  List.iter
    (fun workers ->
      let c, r, f = run ~workers p in
      expect "ordered worker equivalence"
        (c.stop = Planner.Complete && c.rows_committed = 12
        && c.calculations_committed = 30
        && same r rs && f = Some c))
    [ 1; 2; 3 ];
  let d = Domain.spawn (fun () -> run ~workers:2 p) in
  expect "concurrent plan reuse" (same (run ~workers:3 p) (Domain.join d));
  let c, r, f = run ~cancel_at:3 p in
  expect "cancel committed prefix"
    (c.stop = Planner.Cancelled && c.rows_committed = 3
    && List.length r = 3
    && f = Some c);
  List.iter
    (fun throws ->
      let c, r, f = run ~fail_at:3 ~throws p in
      expect "sink failure prefix"
        (match c.stop with
        | Planner.Sink_failure _ ->
            c.rows_committed = 3 && List.length r = 3 && f = None
        | _ -> false))
    [ false; true ];
  let c = Planner.cancellation () in
  Planner.cancel c;
  let complete =
    P.execute p ~workers:2 ~cancellation:c ~sink:(function
      | P.Row _ -> failwith "row after precancel"
      | P.Finished _ -> Ok ())
  in
  expect "pre-cancel"
    (complete.stop = Planner.Cancelled && complete.rows_committed = 0);
  let c, _, _ = run ~workers:0 p in
  expect "worker limit"
    (match c.stop with Planner.Worker_failure _ -> true | _ -> false);
  let q = ok (compile ~snapshot_id:"other" portfolio points) in
  expect "foreign tile" (Result.is_error (P.evaluate_tile p (P.tile q 0)));
  let altered = Array.copy portfolio in
  altered.(0) <- position ~strike:91. constant outputs;
  let q = ok (compile altered points) in
  expect "full model identity" ((P.explain p).plan_id <> (P.explain q).plan_id);
  let q =
    ok
      (compile
         ~limits:{ limits with max_schedule_events = 63 }
         portfolio points)
  in
  expect "resource identity" ((P.explain p).plan_id <> (P.explain q).plan_id);
  let empty = ok (compile [||] points) in
  let c, _, _ = run empty in
  expect "empty plan" (c.stop = Planner.Complete && c.rows_committed = 0);
  expect "output buffer bound"
    (Result.is_error
       (compile
          ~limits:{ limits with max_buffered_results = 0 }
          portfolio points));
  expect "empty output rows still bounded"
    (Result.is_error
       (compile
          ~limits:{ limits with max_buffered_results = 0 }
          [| position constant [] |]
          [| point 0 |]));
  expect "workspace bound"
    (Result.is_error
       (compile
          ~limits:{ limits with max_solver_workspace_bytes = 0 }
          portfolio points));
  expect "schedule bound"
    (Result.is_error
       (compile
          ~limits:{ limits with max_schedule_events = 0 }
          portfolio points));
  expect "duplicate identity"
    (Result.is_error (compile [| portfolio.(0); portfolio.(0) |] points));
  expect "unsupported coordinate"
    (Result.is_error
       (compile portfolio
          [|
            point
              ~shocks:
                [
                  Scenario.
                    {
                      factor = "S";
                      field = Normal_volatility;
                      adjustment = Replace 1.;
                    };
                ]
              0;
          |]));
  let rv = ok (Scenario.linear ~first:1. ~step:0. ~count:1000000000) in
  let huge =
    ok
      (Scenario.cartesian
         [
           Scenario.Market
             { factor = "S"; field = Spot; mode = Absolute; range = rv };
           Scenario.Market
             {
               factor = "S";
               field = Lognormal_volatility;
               mode = Absolute;
               range = rv;
             };
         ])
  in
  expect "calculation overflow"
    (Result.is_error
       (P.compile ~snapshot_id:"huge" ~base_day:0
          ~day_count:Planner.Actual_365_fixed
          ~cash_at_valuation:P.Before_payment ~portfolio ~market ~scenarios:huge
          ~limits:
            { limits with max_scenarios = max_int; max_calculations = max_int }));
  expect "manifest records exact identity" (String.length (P.manifest p) > 500)

let cash_dates () =
  let cash = [| P.{ day = 365; amount = 10. } |] in
  let contract id expiry_side =
    position ~id ~cash:(Some cash)
      ~exercise:
        (P.American { opening = { day = 365; side = expiry_side }; expiry_side })
      constant [ B.Output price ]
  in
  let portfolio =
    [| contract "before" A.Before_cash; contract "after" A.After_cash |]
  in
  let p = ok (compile portfolio [| point 365 |])
  and q =
    ok (compile ~cash_at_valuation:P.After_payment portfolio [| point 365 |])
  in
  let before = rows p and after = rows q in
  expect "cash before exercise payoff"
    ((single_price (List.nth before 0)).value = 10.);
  expect "joint terminal cash payoff"
    ((single_price (List.nth before 1)).value = 0.);
  expect "past terminal instant"
    (match (List.nth after 0).outcomes with
    | [ P.Outcome (_, Error P.Post_expiry) ] -> true
    | _ -> false);
  expect "after-cash spot not debited twice"
    ((single_price (List.nth after 1)).value = 10.);
  let finite =
    position ~cash:(Some cash)
      ~exercise:(P.Bermudan [| P.{ day = 365; side = A.After_cash } |])
      constant [ B.Output price ]
  in
  expect "Bermudan retains today's exercise right"
    ((single_price
        (List.hd
           (rows
              (ok
                 (compile ~cash_at_valuation:P.After_payment [| finite |]
                    [| point 365 |])))))
       .value = 10.);
  let saved = P.manifest p in
  cash.(0) <- P.{ day = 0; amount = 999. };
  portfolio.(0) <- position constant [];
  expect "frozen cash preserves terminal payoff"
    ((single_price (List.nth (rows p) 1)).value = 0.);
  expect "cash arrays frozen" (P.manifest p = saved && same (rows p) before);
  let bad =
    position
      ~cash:(Some [| P.{ day = 90; amount = 1. }; { day = 80; amount = 1. } |])
      constant [ B.Output price ]
  in
  expect "roll cannot hide unsorted cash"
    (Result.is_error (compile [| bad |] [| point 200 |]));
  let ds =
    P.
      [|
        { day = 90; side = A.Regular };
        { day = 180; side = A.Regular };
        { day = 365; side = A.Regular };
      |]
  in
  let bermudan =
    position ~side:Side.Put ~exercise:(P.Bermudan ds)
      (P.Constant { rate = 0.25; dividend_yield = 0.; volatility = vol 0. })
      [ B.Output price ]
  in
  let p =
    ok
      (compile
         ~market:P.[| { name = "S"; spot = 0. } |]
         [| bermudan |]
         [| point 181 |])
  in
  let a =
    ok
      (A.admit_bermudan
         {
           inputs with
           spot = 0.;
           rate = 0.25;
           time_to_expiry = 184. /. 365.;
           opens_at = 184. /. 365.;
           volatility = vol 0.;
         }
         A.[| { time = 184. /. 365.; side = Regular } |])
  in
  let expected = ok (A.price cfg a Side.Put) in
  expect "finite roll adds no rights"
    (same (single_price (List.hd (rows p))) expected && expected.value < 90.);
  ds.(2) <- P.{ day = 181; side = A.Regular };
  expect "exercise arrays frozen"
    (same (single_price (List.hd (rows p))) expected)

let piecewise_dates () =
  let r = [| (180, 0.04) |]
  and q = [| (180, 0.02) |]
  and vs = [| (180, vol 0.3) |] in
  let model =
    P.Piecewise
      {
        rate = { initial = 0.01; changes = r };
        dividend_yield = { initial = 0.; changes = q };
        volatility = { initial = vol 0.2; changes = vs };
      }
  in
  let exercise =
    P.American
      { opening = { day = 365; side = A.Regular }; expiry_side = A.Regular }
  in
  let position =
    position ~exercise model
      B.[ Output price; Output (Greeks (cfg, greek_cfg)) ]
  in
  let plan =
    ok
      (compile [| position |]
         [|
           point
             ~shocks:
               [
                 Scenario.
                   {
                     factor = "S";
                     field = Lognormal_volatility;
                     adjustment = Scale 2.;
                   };
               ]
             180;
         |])
  in
  let input =
    A.Piecewise.
      {
        spot = 100.;
        strike = 90.;
        time_to_expiry = 185. /. 365.;
        opens_at = 185. /. 365.;
        rate =
          ok (Rate.create ~horizon:(185. /. 365.) ~initial:0.04 ~changes:[||]);
        dividend_yield =
          ok (Yield.create ~horizon:(185. /. 365.) ~initial:0.02 ~changes:[||]);
        volatility =
          ok
            (Volatility.create ~horizon:(185. /. 365.) ~initial:(vol 0.6)
               ~changes:[||]);
      }
  in
  let admitted = ok (A.Piecewise.admit input) in
  let expected =
    B.evaluate
      (B.Request
         {
           id = "p";
           model = B.Piecewise admitted;
           side = Side.Call;
           outputs = B.[ Output price; Output (Greeks (cfg, greek_cfg)) ];
         })
  in
  let convert (B.Outcome (op, r)) =
    P.Outcome (op, Result.map_error (fun e -> P.Scalar e) r)
  in
  let expected_value = (ok (A.Piecewise.price cfg admitted Side.Call)).value in
  expect "active knot sets numerical target"
    (abs_float ((single_price (List.hd (rows plan))).value -. expected_value)
    < 1e-10);
  let earlier = ok (compile [| position |] [| point 90 |]) in
  let remaining = 275. /. 365. and knot = 90. /. 365. in
  let explicit =
    ok
      (A.Piecewise.admit
         A.Piecewise.
           {
             spot = 100.;
             strike = 90.;
             time_to_expiry = remaining;
             opens_at = remaining;
             rate =
               ok
                 (Rate.create ~horizon:remaining ~initial:0.01
                    ~changes:[| (knot, 0.04) |]);
             dividend_yield =
               ok
                 (Yield.create ~horizon:remaining ~initial:0.
                    ~changes:[| (knot, 0.02) |]);
             volatility =
               ok
                 (Volatility.create ~horizon:remaining ~initial:(vol 0.2)
                    ~changes:[| (knot, vol 0.3) |]);
           })
  in
  expect "future knots roll by integer day differences"
    (abs_float
       ((single_price (List.hd (rows earlier))).value
      -. (ok (A.Piecewise.price cfg explicit Side.Call)).value)
    < 1e-10);
  expect "right-continuous coefficient roll and parallel shock"
    (same (List.hd (rows plan)).outcomes (List.map convert expected.outcomes));
  let original = rows plan in
  r.(0) <- (180, 9.);
  q.(0) <- (180, 9.);
  vs.(0) <- (180, vol 9.);
  expect "coefficient arrays frozen" (same (rows plan) original);
  let limit = { batch_limits with max_requests = 1 } in
  let fixed =
    ok
      (B.compile ~limits:limit
         [|
           B.Request
             {
               id = "curve";
               model = B.Piecewise admitted;
               side = Side.Call;
               outputs = B.[ Output price ];
             };
         |])
  in
  expect "piecewise fixed batch"
    (match (B.execute fixed).(0).outcomes with
    | [ B.Outcome (B.Price _, Ok p) ] -> p.value > 0.
    | _ -> false)

let assurance_and_identity () =
  let cash =
    A.
      {
        valuation_side = Regular;
        opening_side = Regular;
        expiry_side = After_cash;
        dividends = [| { time = 1.; amount = 10. } |];
      }
  in
  let cash_admitted = ok (A.admit_cash inputs cash) in
  let cash_request =
    B.Request
      {
        id = "cash";
        model = B.Constant cash_admitted;
        side = Side.Put;
        outputs =
          B.
            [
              Output price;
              Output (Certified_price certificate);
              Output (Implied (inverse, quote));
            ];
      }
  in
  let result =
    B.execute (ok (B.compile ~limits:batch_limits [| cash_request |]))
  in
  expect "cash batch scalar price"
    (match result.(0).outcomes with
    | B.Outcome (B.Price _, p) :: _ ->
        same p
          (Result.map_error
             (fun e -> B.Pricing e)
             (A.price cfg cash_admitted Side.Put))
    | _ -> false);
  expect "cash assurance and inverse failures preserved"
    (match result.(0).outcomes with
    | [
     _;
     B.Outcome
       ( B.Certified_price _,
         Error
           (B.Certification
              (A.Certified.Unsupported_capability Cash_specification)) );
     B.Outcome
       (B.Implied _, Error (B.Inverse A.Implied_volatility.Unsupported_cash_put));
    ] ->
        true
    | _ -> false);
  let e =
    P.American
      { opening = { day = 0; side = A.Regular }; expiry_side = A.After_cash }
  in
  let dividend = P.[| { day = 365; amount = 10. } |] in
  let continuous =
    ok
      (compile
         [|
           position ~cash:(Some dividend) ~exercise:e constant
             [ B.Output price ];
         |]
         [| point 365 |])
  in
  expect "continuous rights retain pre-cash exercise"
    ((single_price (List.hd (rows continuous))).value = 10.);
  let rights =
    P.
      [|
        { day = 180; side = A.Before_cash };
        { day = 180; side = A.After_cash };
        { day = 365; side = A.Regular };
      |]
  in
  let cash = P.[| { day = 180; amount = 5. } |] in
  let build valuation =
    ok
      (compile ~cash_at_valuation:valuation
         [|
           position ~cash:(Some cash) ~exercise:(P.Bermudan rights) constant
             [ B.Output price ];
         |]
         [| point 180 |])
  in
  List.iter
    (fun valuation ->
      let after = valuation = P.After_payment in
      let scalar_cash =
        A.
          {
            valuation_side = (if after then After_cash else Before_cash);
            opening_side = (if after then After_cash else Before_cash);
            expiry_side = Regular;
            dividends = [| { time = 0.; amount = 5. } |];
          }
      in
      let ds =
        if after then
          A.
            [|
              { time = 0.; side = After_cash };
              { time = 185. /. 365.; side = Regular };
            |]
        else
          A.
            [|
              { time = 0.; side = Before_cash };
              { time = 0.; side = After_cash };
              { time = 185. /. 365.; side = Regular };
            |]
      in
      let a =
        ok
          (A.admit_bermudan ~cash:scalar_cash
             { inputs with time_to_expiry = 185. /. 365. }
             ds)
      in
      expect "coincident Bermudan rights match exact remaining instants"
        (same
           (single_price (List.hd (rows (build valuation))))
           (ok (A.price cfg a Side.Call))))
    [ P.Before_payment; P.After_payment ];
  let bare = [| position constant [ B.Output price ] |] in
  let base = ok (compile bare [| point 30 |]) in
  let day360 = ok (compile ~day_count:Planner.Actual_360 bare [| point 30 |]) in
  let a = ok (A.admit { inputs with time_to_expiry = 335. /. 360. }) in
  expect "ACT360 is a single day-fraction division"
    (same (single_price (List.hd (rows day360))) (ok (A.price cfg a Side.Call)));
  expect "day count identity"
    ((P.explain base).plan_id <> (P.explain day360).plan_id);
  let altered_cfg =
    ok
      (A.configure ~tolerance:9. ~space_cells:16 ~time_steps:16
         ~domain_expansions:2 ~limits:cfg.limits)
  in
  let variants =
    [
      [|
        position constant
          [
            B.Output
              (B.Price
                 {
                   pricing = altered_cfg;
                   premium = false;
                   exercise_regions = false;
                 });
          ];
      |];
      [|
        position constant
          [
            B.Output
              (B.Price
                 { pricing = cfg; premium = true; exercise_regions = false });
          ];
      |];
      [|
        position
          ~exercise:
            (P.Bermudan
               P.
                 [|
                   { day = 0; side = A.Regular };
                   { day = 365; side = A.Regular };
                 |])
          constant [ B.Output price ];
      |];
      [|
        position
          (P.Constant { rate = 0.04; dividend_yield = 0.; volatility = vol 0.2 })
          [ B.Output price ];
      |];
      [|
        position constant
          [
            B.Output (B.Implied (inverse, ok (A.Implied_volatility.quote 12.)));
          ];
      |];
      [| position constant [ B.Output (B.Certified_price certificate) ] |];
    ]
  in
  List.iter
    (fun portfolio ->
      expect "operation/model identities differ"
        ((P.explain (ok (compile portfolio [| point 30 |]))).plan_id
       <> (P.explain base).plan_id))
    variants;
  let getid outs =
    (P.explain (ok (compile [| position constant outs |] [| point 0 |])))
      .plan_id
  in
  expect "quote identity"
    (getid B.[ Output (Implied (inverse, quote)) ]
    <> getid
         B.[ Output (Implied (inverse, ok (A.Implied_volatility.quote 12.))) ]);
  let wider =
    ok
      (A.Implied_volatility.configure ~pricing:cfg ~lower:(vol 0.05)
         ~upper:(vol 0.6) ~width:0.02 ~max_evaluations:32)
  in
  expect "inverse settings identity"
    (getid B.[ Output (Implied (inverse, quote)) ]
    <> getid B.[ Output (Implied (wider, quote)) ]);
  expect "output order identity"
    (getid B.[ Output price; Output (Certified_price certificate) ]
    <> getid B.[ Output (Certified_price certificate); Output price ]);
  expect "market count bound"
    (Result.is_error
       (compile
          ~limits:{ limits with max_market_factors = 0 }
          bare
          [| point 0 |]));
  let p = ok (compile bare [| point 0 |]) in
  let expected = rows p in
  let evaluated = ok (P.evaluate_tile p (P.tile p 0)) in
  evaluated.(0) <-
    { (evaluated.(0)) with instrument_id = "corrupt"; outcomes = [] };
  expect "plan output arrays fresh" (same (rows p) expected)

let () =
  batch ();
  constant_dates ();
  cash_dates ();
  piecewise_dates ();
  assurance_and_identity ();
  print_endline
    "American compiled: typed scalar equivalence, dates, ownership, bounded \
     execution and prefixes pass"
