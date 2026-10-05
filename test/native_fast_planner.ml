open Morphiq_risk
module P = Planner
module F = P.Fast
module S = Scenario

let ok = function Ok x -> x | Error _ -> failwith "native planner admission"
let check b s = if not b then failwith s

let same a b =
  Marshal.to_string a [ Marshal.No_sharing ]
  = Marshal.to_string b [ Marshal.No_sharing ]

let nv = ok (Vol.normal 10.)

let market =
  [|
    P.{ name = "N"; market = Normal_market { forward = 100.; volatility = nv } };
  |]

let portfolio =
  Array.init 129 (fun i ->
      let side = if i mod 2 = 0 then Side.Call else Side.Put in
      let distance = 5. +. (float (i mod 31) /. 2.) in
      P.
        {
          id = string_of_int i;
          factor = "N";
          rate_factor = "r";
          currency = "USD";
          quantity = float (i - 65);
          model = Bachelier;
          strike = (100. +. if side = Side.Call then distance else -.distance);
          expiry_day = (if i mod 17 = 0 then 0 else 365);
          rate = 0.02;
          side;
        })

let point offset_days shocks = S.{ offset_days; shocks }
let shock field adjustment = S.{ factor = "N"; field; adjustment }

let points =
  [|
    point 0 [];
    point 30
      [ shock S.Forward (S.Add 2.); shock S.Normal_volatility (S.Scale 1.2) ];
    point 365 [];
    point 366 [];
    point 30 [ shock S.Normal_volatility (S.Replace (-1.)) ];
    point 366 [ shock S.Normal_volatility (S.Replace (-1.)) ];
    point 0 [ shock S.Forward (S.Scale Float.max_float) ];
  |]

let scenarios = ok (S.paired points)

let plan ?(portfolio = portfolio) tile_rows =
  ok
    (F.compile ~snapshot_id:"native-tiles" ~base_day:0
       ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
       ~limits:
         {
           max_instruments = Array.length portfolio;
           max_scenarios = 7;
           max_calculations = Array.length portfolio * 7;
           tile_rows;
           max_workers = 4;
           max_buffered_results = tile_rows * 4;
         })

let expected (portfolio : P.position array) (r : F.row) =
  let position = portfolio.(r.instrument_index)
  and point = points.(r.scenario_id) in
  if point.offset_days > position.expiry_day then Error F.Post_expiry
  else
    let forward, volatility =
      List.fold_left
        (fun (f, v) (s : S.shock) ->
          match s.field with
          | S.Forward -> (S.apply s.adjustment f, v)
          | S.Normal_volatility -> (f, S.apply s.adjustment v)
          | _ -> failwith "test shock")
        (100., 10.) point.shocks
    in
    match Vol.normal volatility with
    | Error e -> Error (F.Scalar (Batch.Fast.Invalid_input e))
    | Ok sigma ->
        Result.map_error
          (fun e -> F.Scalar e)
          (Batch.Fast.evaluate
             (Batch.Fast.Price
                ( Batch.Bachelier,
                  {
                    forward;
                    strike = position.strike;
                    time_to_expiry =
                      float (position.expiry_day - point.offset_days) /. 365.;
                    rate = position.rate;
                  },
                  position.side,
                  sigma )))

let trace ?(portfolio = portfolio) p workers =
  let rows = ref [] in
  let completion =
    F.execute p ~workers ~cancellation:(P.cancellation ()) ~sink:(function
      | F.Row row ->
          check
            (same row.price (expected portfolio row))
            "native tile scalar original-input outcome";
          let pos = portfolio.(row.instrument_index) in
          check
            (row.instrument_id = pos.id && row.factor_id = pos.factor
            && row.currency = pos.currency
            && row.quantity = pos.quantity
            && row.coordinate = P.Normal)
            "native tile metadata";
          rows := row :: !rows;
          Ok ()
      | F.Finished _ -> Ok ())
  in
  check
    (completion.stop = P.Complete
    && completion.rows_committed = Array.length portfolio * 7
    && completion.calculations_committed = Array.length portfolio * 7)
    "native tile complete coverage";
  (List.rev !rows, completion)

let () =
  let baseline = trace (plan 1) 1 in
  List.iter
    (fun tile_rows ->
      let p = plan tile_rows in
      List.iter
        (fun workers ->
          check
            (same (trace p workers) baseline)
            "native tiles worker/tile replay")
        [ 1; 2; 4 ];
      let cancel = P.cancellation () and rows = ref 0 in
      let c =
        F.execute p ~workers:4 ~cancellation:cancel ~sink:(function
          | F.Row _ ->
              incr rows;
              if !rows = 17 then P.cancel cancel;
              Ok ()
          | F.Finished _ -> Ok ())
      in
      check
        (c.stop = P.Cancelled && c.rows_committed = 17)
        "native tile cancellation";
      let rows = ref 0 in
      let c =
        F.execute p ~workers:4 ~cancellation:(P.cancellation ()) ~sink:(function
          | F.Row _ ->
              incr rows;
              if !rows = 7 then Error "intentional native sink failure"
              else Ok ()
          | F.Finished _ -> Ok ())
      in
      check
        (c.stop = P.Sink_failure "intentional native sink failure"
        && c.rows_committed = 6)
        "native sink failure commit boundary";
      check (same (trace p 2) baseline) "native worker cleanup/reuse")
    [ 31; 32; 33; 64; 65; 128 ];
  let large =
    Array.init 513 (fun i ->
        { (portfolio.(i mod Array.length portfolio)) with id = string_of_int i })
  in
  let baseline_large = trace ~portfolio:large (plan ~portfolio:large 1) 1 in
  List.iter
    (fun tile_rows ->
      let p = plan ~portfolio:large tile_rows in
      List.iter
        (fun workers ->
          check
            (same (trace ~portfolio:large p workers) baseline_large)
            "native preparation chunks preserve logical tiles and final tails")
        [ 1; 2; 4 ])
    [ 256; 257; 512; 513 ];
  let p = plan 65 in
  let d = Domain.spawn (fun () -> trace p 2) in
  check (same (trace p 2) (Domain.join d)) "native concurrent planner reuse";
  print_endline
    "native Fast planner: original-input scalar replay, metadata, \
     expiry/refusal priority, tile/worker order, cancellation, sink failures \
     and concurrent reuse pass"
