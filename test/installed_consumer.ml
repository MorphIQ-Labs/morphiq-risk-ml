(* Public-package-only acceptance: compiled outside Dune's source/build tree. *)
open Morphiq_risk
module P = Planner
module S = Scenario

let ok = function Ok x -> x | Error _ -> failwith "unexpected refusal"
let check b s = if not b then failwith s
let finite x = Float.is_finite x
let vol = ok (Vol.lognormal 0.2)
let normal_vol = ok (Vol.normal 10.)

let batch_model : type i c. (i, c) Batch.model -> i -> c Vol.t -> unit =
 fun model inputs volatility ->
  let request q =
    Batch.Request
      (model, inputs, Side.Call, Batch.Evaluate (volatility, q, 1e-10))
  in
  let requests = [| request Production.Price; request Production.Delta |] in
  let results = Batch.run requests in
  check (results = Array.map Batch.evaluate requests) "batch/scalar dispatch";
  Array.iter
    (fun result ->
      let (c : float Production.certified) = ok result in
      check
        (finite c.value && finite c.absolute_error && c.absolute_error >= 0.
       && c.absolute_error <= 1e-10)
        "finite bounded certificate")
    results;
  let price = (ok results.(0)).value in
  (match
     ok
       (Batch.evaluate
          (Batch.Request (model, inputs, Side.Call, Batch.Implied price)))
   with
  | Iv.Root v -> check (Vol.to_float v > 0.) "positive IV"
  | _ -> failwith "expected positive IV");
  check
    (Result.is_error
       (Batch.evaluate
          (Batch.Request (model, inputs, Side.Call, Batch.Implied (-1.)))))
    "invalid quote";
  check
    (match
       Batch.evaluate
         (Batch.Request
            ( model,
              inputs,
              Side.Call,
              Batch.Evaluate (volatility, Production.Price, -1.) ))
     with
    | Error Production.Invalid_accuracy -> true
    | _ -> false)
    "invalid accuracy"

let limits =
  P.
    {
      max_instruments = 10;
      max_scenarios = 10;
      max_calculations = 100;
      tile_rows = 2;
      max_workers = 2;
      max_buffered_results = 20;
      max_groups = 10;
    }

let portfolio =
  [|
    P.
      {
        id = "a";
        factor = "F";
        rate_factor = "USD-rate";
        currency = "USD";
        quantity = 2.;
        model = Black76;
        strike = 100.;
        expiry_day = 30;
        rate = 0.02;
        side = Side.Call;
      };
    P.
      {
        id = "b";
        factor = "F";
        rate_factor = "USD-rate";
        currency = "USD";
        quantity = -1.;
        model = Black76;
        strike = 100.;
        expiry_day = 30;
        rate = 0.02;
        side = Side.Call;
      };
  |]

let market =
  [|
    P.
      {
        name = "F";
        market = Forward_market { forward = 100.; volatility = vol };
      };
  |]

let compile scenarios =
  P.compile ~snapshot_id:"installed-consumer" ~base_day:0
    ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
    ~lognormal_outputs:
      [ P.Output (Production.Price, 1e-10); P.Output (Production.Delta, 1e-10) ]
    ~normal_outputs:[] ~output_mode:P.Stream ~limits

let execute workers plan =
  let events = ref [] in
  let status =
    P.execute plan ~workers ~cancellation:(P.cancellation ())
      ~sink:(fun event ->
        events := event :: !events;
        Ok ())
  in
  check (status.stop = P.Complete) "complete execution";
  (List.rev !events, status)

let () =
  let inputs =
    Black.Black76_carry.
      { forward = 100.; strike = 100.; time_to_expiry = 1.; rate = 0.02 }
  in
  let admitted = ok (Production.Black76.admit inputs) in
  let certificate =
    ok
      (Production.Black76.evaluate admitted Side.Call vol Production.Price
         ~max_error:1e-10)
  in
  check
    (Batch.evaluate
       (Batch.Request
          ( Batch.Black76,
            inputs,
            Side.Call,
            Batch.Evaluate (vol, Production.Price, 1e-10) ))
    = Ok certificate)
    "installed scalar price recovery";
  (match
     ok (Production.Black76.implied admitted Side.Call certificate.value)
   with
  | Iv.Root root -> check (Vol.to_float root > 0.) "installed scalar IV"
  | _ -> failwith "scalar IV classification");
  batch_model Batch.Bsm
    {
      spot = 100.;
      strike = 100.;
      time_to_expiry = 1.;
      rate = 0.02;
      dividend_yield = 0.01;
    }
    vol;
  batch_model Batch.Black76
    { forward = 100.; strike = 100.; time_to_expiry = 1.; rate = 0.02 }
    vol;
  batch_model Batch.Displaced
    {
      forward = -2.;
      strike = -1.;
      displacement = 120.;
      time_to_expiry = 1.;
      rate = 0.02;
    }
    vol;
  batch_model Batch.Bachelier
    { forward = -2.; strike = -1.; time_to_expiry = 1.; rate = 0.02 }
    normal_vol;
  check (Batch.run [||] = [||]) "empty batch";
  let days = [| 0; 30; 31 |] in
  let scenarios = ok (S.cartesian [ S.Time days ]) in
  days.(0) <- 99;
  check ((S.point scenarios 0).offset_days = 0) "frozen scenarios";
  let paired = ok (S.paired (Array.init 3 (S.point scenarios))) in
  let plan = ok (compile scenarios) in
  let ex = P.explain plan in
  check
    (ex.instruments = 2 && ex.scenarios = 3 && ex.calculations = 12
   && ex.groups = 2)
    "inspectable plan";
  let events, status = execute 1 plan in
  check
    (status.rows_committed = 6 && status.calculations_committed = 12)
    "coverage";
  check
    (execute 2 plan = (events, status))
    "worker-independent order and values";
  check
    (execute 1 (ok (compile paired)) = (events, status))
    "paired/cartesian meaning";
  let saw_expiry = ref false
  and saw_post = ref false
  and saw_partial = ref false in
  List.iter
    (function
      | P.Row r when r.scenario_id = 1 ->
          saw_expiry := true;
          List.iter
            (function
              | P.Outcome (Production.Price, Ok c) ->
                  check (c.value = 0.) "expiry payoff"
              | P.Outcome
                  (Production.Delta, Error (P.Scalar (Production.Unsupported _)))
                ->
                  ()
              | _ -> failwith "expiry outcome")
            r.outcomes
      | P.Row r when r.scenario_id = 2 ->
          saw_post := true;
          List.iter
            (fun (P.Outcome (_, x)) ->
              check (x = Error P.Post_expiry) "post-expiry")
            r.outcomes
      | P.Summary s ->
          if s.failed > 0 then (
            saw_partial := true;
            check (not s.complete) "incomplete total")
          else
            check
              (s.complete && Option.is_some s.successful_subset)
              "complete total"
      | _ -> ())
    events;
  check
    (!saw_expiry && !saw_post && !saw_partial)
    "boundary witnesses exercised";
  let cancellation = P.cancellation () in
  P.cancel cancellation;
  let stopped =
    P.execute plan ~workers:2 ~cancellation ~sink:(fun _ -> Ok ())
  in
  check
    (stopped.stop = P.Cancelled && stopped.rows_committed = 0)
    "cancellation";
  let stopped =
    P.execute plan ~workers:2 ~cancellation:(P.cancellation ()) ~sink:(fun _ ->
        Error "closed")
  in
  check
    (stopped.stop = P.Sink_failure "closed" && stopped.rows_committed = 0)
    "sink failure";
  print_endline version
