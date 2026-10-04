open Morphiq_risk
module P = Production

let ok = function Ok x -> x | Error _ -> failwith "unexpected admission"
let require name yes = if not yes then failwith name

let () =
  (* At ATM with r=0, Bachelier vega is sqrt(T)/sqrt(2*pi), and
     delta is +/-1/2. Half-inverse maturity overflows at this exact T;
     it belongs to other derivatives and cannot poison these results. *)
  let inputs =
    Bachelier.
      { forward = 0.; strike = 0.; time_to_expiry = 0x1p-1060; rate = 0. }
  in
  let admitted = ok (P.Bachelier.admit inputs) and sigma = ok (Vol.normal 1.) in
  let requests =
    P.
      [
        Request (Veta, Units.volatility_time_rate Float.max_float);
        Request (Vega, Units.per_volatility Float.max_float);
        Request (Charm, Units.time_rate Float.max_float);
        Request (Delta, Float.max_float);
        Request (Color, Units.time_rate Float.max_float);
        Request (Price, Float.max_float);
        Request (Vega, Units.per_volatility Float.max_float);
      ]
  in
  List.iter
    (fun side ->
      List.iter
        (fun requests ->
          let results =
            P.Bachelier.evaluate_many admitted side sigma requests
          in
          require "all requested outputs survive partial failure"
            (List.length results = 7);
          let successes = ref 0 and failures = ref 0 in
          List.iter
            (fun (outcome : Vol.normal P.outcome) ->
              match outcome with
              | P.Outcome (P.Veta, Error P.Numerical_failure)
              | P.Outcome (P.Charm, Error P.Numerical_failure)
              | P.Outcome (P.Color, Error P.Numerical_failure) ->
                  incr failures
              | P.Outcome (P.Vega, Ok c) ->
                  let scaled = Float.ldexp (c.value :> float) 530 in
                  require "independent normal ATM vega"
                    (scaled > 0.398 && scaled < 0.399);
                  require "finite vega radius"
                    (Float.is_finite (c.absolute_error :> float));
                  incr successes
              | P.Outcome (P.Price, Ok c) ->
                  let scaled = Float.ldexp c.value 530 in
                  require "independent normal ATM price"
                    (scaled > 0.398 && scaled < 0.399);
                  incr successes
              | P.Outcome (P.Delta, Ok c) ->
                  require "independent normal ATM delta"
                    (c.value = if side = Side.Call then 0.5 else -0.5);
                  incr successes
              | _ ->
                  failwith
                    "deferred derivative failure contaminated another output")
            results;
          require "partial failure counts" (!successes = 4 && !failures = 3))
        [ requests; List.rev requests ])
    [ Side.Call; Side.Put ];
  print_endline
    "shared Greeks: deferred partial failures retain independent ATM price, \
     delta and vega"
