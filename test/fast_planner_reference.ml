open Morphiq_risk
module P = Planner
module F = P.Fast

let ok = function Ok x -> x | Error _ -> failwith "reference plan refusal"
let same a b = Marshal.to_string a [] = Marshal.to_string b []

(* A civil-day API cannot represent every fixture maturity. Retain only exact
   round trips; never round a fixture input and compare against its old oracle. *)
let date t =
  List.find_map
    (fun (convention, denominator) ->
      let days = t *. denominator in
      if
        Float.is_finite days && days >= 0. && days <= 1e9
        && days = Float.floor days
        && float (int_of_float days) /. denominator = t
      then Some (convention, int_of_float days)
      else None)
    [ (P.Actual_365_fixed, 365.); (P.Actual_360, 360.) ]

let unpack (Batch.Fast.Price (model, inputs, side, sigma)) =
  let kind, market, strike, time, rate =
    match model with
    | Batch.Bsm ->
        ( P.Bsm { dividend_yield = inputs.dividend_yield },
          P.Spot_market { spot = inputs.spot; volatility = sigma },
          inputs.strike,
          inputs.time_to_expiry,
          inputs.rate )
    | Batch.Black76 ->
        ( P.Black76,
          P.Forward_market { forward = inputs.forward; volatility = sigma },
          inputs.strike,
          inputs.time_to_expiry,
          inputs.rate )
    | Batch.Displaced ->
        ( P.Displaced inputs.displacement,
          P.Forward_market { forward = inputs.forward; volatility = sigma },
          inputs.strike,
          inputs.time_to_expiry,
          inputs.rate )
    | Batch.Bachelier ->
        ( P.Bachelier,
          P.Normal_market { forward = inputs.forward; volatility = sigma },
          inputs.strike,
          inputs.time_to_expiry,
          inputs.rate )
  in
  Option.map
    (fun (day_count, expiry_day) ->
      ( day_count,
        P.
          {
            id = "fixture";
            factor = "market";
            rate_factor = "rate";
            currency = "USD";
            quantity = 1.;
            model = kind;
            strike;
            expiry_day;
            rate;
            side;
          },
        P.{ name = "market"; market } ))
    (date time)

let () =
  let cases = Fast_reference_cases.load Sys.argv in
  let covered = ref 0 and excluded = ref 0 in
  let counts = Hashtbl.create 8 in
  Array.iteri
    (fun index (request, expected) ->
      match unpack request with
      | None -> incr excluded
      | Some (day_count, position, market) ->
          incr covered;
          let name =
            match position.model with
            | P.Bsm _ -> "bsm"
            | Black76 -> "black76"
            | Displaced _ -> "displaced"
            | Bachelier -> "bachelier"
          in
          Hashtbl.replace counts name
            (1 + Option.value ~default:0 (Hashtbl.find_opt counts name));
          let plan =
            ok
              (F.compile ~snapshot_id:"fixture" ~base_day:0 ~day_count
                 ~portfolio:[| position |] ~market:[| market |]
                 ~scenarios:(ok (Scenario.cartesian []))
                 ~limits:
                   {
                     max_instruments = 1;
                     max_scenarios = 1;
                     max_calculations = 1;
                     tile_rows = 1;
                     max_workers = 1;
                     max_buffered_results = 1;
                   })
          in
          let rows = ok (F.evaluate_tile plan (F.tile plan 0)) in
          let want = Result.map_error (fun e -> F.Scalar e) expected in
          if Array.length rows <> 1 || not (same rows.(0).price want) then
            failwith
              (Printf.sprintf "planner original fixture mismatch row %d" index))
    cases;
  List.iter
    (fun name ->
      let n = Hashtbl.find counts name in
      if n = 0 then failwith "missing model";
      Printf.printf "fast planner fixture %s: %d\n" name n)
    [ "bsm"; "black76"; "displaced"; "bachelier" ];
  Printf.printf
    "fast planner: %d exact-maturity scalar outcomes; %d nonrepresentable \
     maturities excluded; %d total fixture rows\n"
    !covered !excluded (Array.length cases)
