open Morphiq_risk
module P = Planner
module F = P.Fast
module S = Scenario

let ok = function Ok x -> x | Error _ -> failwith "unexpected refusal"
let check b s = if not b then failwith s
let equal a b = Marshal.to_string a [] = Marshal.to_string b []
let lv = ok (Vol.lognormal 0.2)
let nv = ok (Vol.normal 2.)

let limits : F.limits =
  {
    max_instruments = 32;
    max_scenarios = 32;
    max_calculations = 1024;
    tile_rows = 3;
    max_workers = 4;
    max_buffered_results = 32;
  }

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

let portfolio =
  Array.init 8 (fun i ->
      let factor, model, strike =
        match i mod 4 with
        | 0 -> ("S", P.Bsm { dividend_yield = 0.01 }, 95.)
        | 1 -> ("F", P.Black76, 105.)
        | 2 -> ("D", P.Displaced 5., -1.)
        | _ -> ("N", P.Bachelier, -1.)
      in
      P.
        {
          id = string_of_int i;
          factor;
          rate_factor = "USD-rate";
          currency = "USD";
          quantity = (if i = 0 then 0. else if i mod 2 = 0 then 1e12 else -7.);
          model;
          strike;
          expiry_day = 365;
          rate = 0.02;
          side = (if i < 4 then Side.Call else Side.Put);
        })

let shock factor field adjustment = S.{ factor; field; adjustment }

let points =
  S.
    [|
      { offset_days = 0; shocks = [] };
      { offset_days = 365; shocks = [] };
      {
        offset_days = 366;
        shocks = [ shock "F" Lognormal_volatility (Replace (-1.)) ];
      };
      {
        offset_days = 30;
        shocks =
          [
            shock "S" Spot (Add 5.);
            shock "S" Lognormal_volatility (Scale 0.5);
            shock "F" Forward (Scale 0.9);
            shock "D" Forward (Replace (-3.));
            shock "N" Forward (Add (-0.5));
          ];
      };
      { offset_days = 0; shocks = [ shock "S" Spot (Replace 0.) ] };
      {
        offset_days = 0;
        shocks = [ shock "F" Lognormal_volatility (Replace (-1.)) ];
      };
    |]

let scenarios = ok (S.paired points)

let compile ?(portfolio = portfolio) ?(market = market) ?(scenarios = scenarios)
    ?(limits = limits) ?(day_count = P.Actual_365_fixed)
    ?(snapshot_id = "fast-test") () =
  F.compile ~snapshot_id ~base_day:0 ~day_count ~portfolio ~market ~scenarios
    ~limits

let expected day_count scenario i =
  let p = portfolio.(i) in
  if scenario = 2 then Error F.Post_expiry
  else if scenario = 5 && i mod 4 = 1 then
    match Vol.lognormal (-1.) with
    | Error e -> Error (F.Scalar (Batch.Fast.Invalid_input e))
    | Ok _ -> failwith "negative volatility admitted"
  else
    let days = if scenario = 1 then 0 else if scenario = 3 then 335 else 365 in
    let time_to_expiry =
      float days
      /.
      match day_count with P.Actual_365_fixed -> 365. | P.Actual_360 -> 360.
    in
    let request =
      match p.model with
      | P.Bsm b ->
          Batch.Fast.Price
            ( Batch.Bsm,
              {
                spot =
                  (if scenario = 3 then 105.
                   else if scenario = 4 then 0.
                   else 100.);
                strike = p.strike;
                time_to_expiry;
                rate = p.rate;
                dividend_yield = b.dividend_yield;
              },
              p.side,
              if scenario = 3 then ok (Vol.lognormal 0.1) else lv )
      | P.Black76 ->
          Batch.Fast.Price
            ( Batch.Black76,
              {
                forward = (if scenario = 3 then 90. else 100.);
                strike = p.strike;
                time_to_expiry;
                rate = p.rate;
              },
              p.side,
              lv )
      | P.Displaced displacement ->
          Batch.Fast.Price
            ( Batch.Displaced,
              {
                forward = (if scenario = 3 then -3. else -2.);
                strike = p.strike;
                displacement;
                time_to_expiry;
                rate = p.rate;
              },
              p.side,
              lv )
      | P.Bachelier ->
          Batch.Fast.Price
            ( Batch.Bachelier,
              {
                forward = (if scenario = 3 then -2.5 else -2.);
                strike = p.strike;
                time_to_expiry;
                rate = p.rate;
              },
              p.side,
              nv )
    in
    Result.map_error (fun e -> F.Scalar e) (Batch.Fast.evaluate request)

let collect ?(workers = 1) plan =
  let events = ref [] in
  let owner = Domain.self () in
  let done_ =
    F.execute plan ~workers ~cancellation:(P.cancellation ()) ~sink:(fun e ->
        check (Domain.self () = owner) "worker called sink";
        events := e :: !events;
        Ok ())
  in
  check (done_.stop = P.Complete) "run incomplete";
  (List.rev !events, done_)

let () =
  List.iter
    (fun day_count ->
      let plan = ok (compile ~day_count ()) in
      let events, done_ = collect plan in
      check
        (done_.rows_committed = 48 && done_.calculations_committed = 48)
        "completion counts";
      let rows =
        List.filter_map
          (function F.Row r -> Some r | F.Finished _ -> None)
          events
      in
      List.iteri
        (fun n (r : F.row) ->
          let scenario = n / 8 and index = n mod 8 in
          check
            (r.scenario_id = scenario && r.instrument_index = index
            && r.instrument_id = string_of_int index)
            "row identity/order";
          check
            (equal r.price (expected day_count scenario index))
            "original-input scenario price";
          check
            (r.quantity = portfolio.(index).quantity
            && r.currency = "USD"
            && r.factor_id = portfolio.(index).factor)
            "unweighted metadata")
        rows;
      List.iter
        (fun workers ->
          check (equal (fst (collect ~workers plan)) events) "worker replay")
        [ 2; 3; 4 ];
      let e = F.explain plan in
      check
        (e.calculations = 48 && e.raw_value_bytes = 384
       && e.buffered_results = 12 && e.tiles = 18)
        "bounded explanation";
      check
        (String.starts_with ~prefix:"planner-fast-replay-v1" (F.manifest plan))
        "fast manifest";
      check
        (Result.is_error
           (F.evaluate_tile
              (ok (compile ~day_count ~snapshot_id:"other" ()))
              (F.tile plan 0)))
        "foreign tile";
      let copy = Array.copy portfolio and markets = Array.copy market in
      let frozen = ok (compile ~day_count ~portfolio:copy ~market:markets ()) in
      copy.(0) <- { (copy.(0)) with strike = 1. };
      markets.(0) <- markets.(1);
      check (equal (fst (collect frozen)) events) "source snapshots";
      let token = P.cancellation () in
      let seen = ref [] in
      let stopped =
        F.execute plan ~workers:3 ~cancellation:token ~sink:(fun event ->
            seen := event :: !seen;
            (match event with
            | F.Row r when r.instrument_index = 2 -> P.cancel token
            | _ -> ());
            Ok ())
      in
      check
        (stopped.stop = P.Cancelled && stopped.rows_committed = 3)
        "cancel prefix";
      check
        (match !seen with F.Finished c :: _ -> c = stopped | _ -> false)
        "cancel marker";
      let count = ref 0 in
      let broken =
        F.execute plan ~workers:2 ~cancellation:(P.cancellation ())
          ~sink:(fun _ ->
            incr count;
            if !count = 4 then Error "sink" else Ok ())
      in
      check
        (broken.stop = P.Sink_failure "sink"
        && broken.rows_committed = 3 && !count = 4)
        "sink failure prefix";
      let token = P.cancellation () in
      P.cancel token;
      let cancelled =
        F.execute plan ~workers:1 ~cancellation:token ~sink:(function
          | F.Row _ -> failwith "pre-cancel row"
          | F.Finished _ -> Ok ())
      in
      check
        (cancelled.stop = P.Cancelled && cancelled.rows_committed = 0)
        "pre-cancel";
      let bad =
        F.execute plan ~workers:5 ~cancellation:(P.cancellation ())
          ~sink:(fun _ -> Ok ())
      in
      check
        (match bad.stop with
        | P.Worker_failure _ -> bad.rows_committed = 0
        | _ -> false)
        "worker policy")
    [ P.Actual_365_fixed; P.Actual_360 ];
  List.iter
    (fun limits ->
      check (Result.is_error (compile ~limits ())) "compile resource policy")
    [
      { limits with max_instruments = 7 };
      { limits with max_scenarios = 5 };
      { limits with max_calculations = 47 };
      { limits with tile_rows = 0 };
      { limits with max_workers = 0 };
      { limits with max_buffered_results = 11 };
    ];
  let duplicate = Array.copy portfolio in
  duplicate.(1) <- duplicate.(0);
  check (Result.is_error (compile ~portfolio:duplicate ())) "duplicate id";
  let mismatched = Array.copy market in
  mismatched.(0) <-
    P.{ name = "S"; market = Normal_market { forward = 100.; volatility = nv } };
  check (Result.is_error (compile ~market:mismatched ())) "coordinate mismatch";
  List.iter
    (fun plan ->
      let events, c = collect plan in
      check (c.rows_committed = 0 && List.length events = 1) "empty job")
    [
      ok (compile ~portfolio:[||] ());
      ok (compile ~scenarios:(ok (S.paired [||])) ());
    ];
  let huge =
    ok
      (S.cartesian
         [
           S.Market
             {
               factor = "S";
               field = Spot;
               mode = Absolute;
               range = ok (S.linear ~first:1. ~step:1. ~count:1000000000);
             };
           S.Market
             {
               factor = "F";
               field = Forward;
               mode = Absolute;
               range = ok (S.linear ~first:1. ~step:1. ~count:1000000000);
             };
         ])
  in
  let unlimited =
    {
      limits with
      max_scenarios = max_int;
      max_calculations = max_int;
      max_buffered_results = max_int;
    }
  in
  check
    (Result.is_error (compile ~scenarios:huge ~limits:unlimited ()))
    "cardinality overflow";
  print_endline
    "fast planner: original-input prices, both date conventions, ownership, \
     worker replay, failures and limits pass"
