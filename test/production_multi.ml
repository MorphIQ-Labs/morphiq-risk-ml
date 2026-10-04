open Morphiq_risk
module P = Production

let ok = function Ok x -> x | Error _ -> failwith "unexpected admission"
let check name condition = if not condition then failwith name
let words x = Marshal.to_string x [ Marshal.No_sharing ]

let requests () =
  P.
    [
      Request (Price, 1e-8);
      Request (Delta, 1e-8);
      Request (Gamma, 1e-8);
      Request (Rho, 1e-8);
      Request (Theta, Units.time_rate 1e-8);
      Request (Vega, Units.per_volatility 1e-8);
      Request (Vanna, Units.per_volatility 1e-8);
      Request (Volga, Units.per_volatility_squared 1e-8);
      Request (Charm, Units.time_rate 1e-8);
      Request (Veta, Units.volatility_time_rate 1e-8);
      Request (Color, Units.time_rate 1e-8);
      Request (Price, 0.);
      Request (Delta, Float.nan);
      Request (Price, -1.);
      Request (Price, Float.infinity);
      Request (Price, 1e-8);
    ]

module Check (A : sig
  include P.MULTI_OUTPUT_MODEL

  val model : (inputs, coordinate) Batch.model
  val inputs : time:float -> rate:float -> inputs
  val vol : float -> coordinate Vol.t
end) =
struct
  let run () =
    List.iter
      (fun time ->
        List.iter
          (fun rate ->
            let inputs = A.inputs ~time ~rate in
            let admitted = ok (A.admit inputs) in
            List.iter
              (fun sigma ->
                List.iter
                  (fun side ->
                    let sigma = A.vol sigma and requests = requests () in
                    let expected =
                      List.map
                        (fun (P.Request (q, limit)) ->
                          P.Outcome
                            ( q,
                              A.evaluate admitted side sigma q ~max_error:limit
                            ))
                        requests
                    in
                    check "ordered scalar word/radius/error identity"
                      (words (A.evaluate_many admitted side sigma requests)
                      = words expected);
                    check "batch admission and shared evaluation identity"
                      (words
                         (Batch.evaluate_many A.model inputs side sigma requests)
                      = words expected);
                    check "reordered outputs retain independent results"
                      (words
                         (A.evaluate_many admitted side sigma
                            (List.rev requests))
                      = words (List.rev expected));
                    check "empty requests"
                      (A.evaluate_many admitted side sigma [] = []))
                  [ Side.Call; Side.Put ])
              [ 0.; 0.2 ])
          [ 0.02; -2048. ])
      [ 0.; 1. ];
    let admitted = ok (A.admit (A.inputs ~time:1. ~rate:0.02)) in
    let requests = requests () in
    let expected side sigma =
      words (A.evaluate_many admitted side (A.vol sigma) requests)
    in
    let a = expected Side.Call 0.2 and b = expected Side.Put 0.3 in
    let worker =
      Domain.spawn (fun () ->
          for _ = 1 to 3 do
            check "concurrent put call-local preparation"
              (expected Side.Put 0.3 = b)
          done)
    in
    for _ = 1 to 3 do
      check "concurrent call call-local preparation" (expected Side.Call 0.2 = a)
    done;
    Domain.join worker
end

module Bsm = Check (struct
  include P.Bsm

  let model = Batch.Bsm

  let inputs ~time ~rate =
    Black.Bsm_carry.
      {
        spot = 100.;
        strike = 95.;
        time_to_expiry = time;
        rate;
        dividend_yield = 0.01;
      }

  let vol x = ok (Vol.lognormal x)
end)

module Black76 = Check (struct
  include P.Black76

  let model = Batch.Black76

  let inputs ~time ~rate =
    Black.Black76_carry.
      { forward = 100.; strike = 95.; time_to_expiry = time; rate }

  let vol x = ok (Vol.lognormal x)
end)

module Displaced = Check (struct
  include P.Displaced

  let model = Batch.Displaced

  (* Shifted sums have nonzero low words. *)
  let inputs ~time ~rate =
    Black.Displaced_carry.
      {
        forward = Float.succ (-0.5);
        strike = -0.25;
        displacement = 0x1p53;
        time_to_expiry = time;
        rate;
      }

  let vol x = ok (Vol.lognormal x)
end)

module Normal = Check (struct
  include P.Bachelier

  let model = Batch.Bachelier

  let inputs ~time ~rate =
    Bachelier.{ forward = -1.; strike = -2.; time_to_expiry = time; rate }

  let vol x = ok (Vol.normal x)
end)

let () =
  let inputs =
    Bachelier.{ forward = 0.; strike = 0.; time_to_expiry = 1.; rate = 0. }
  in
  let admitted = ok (P.Bachelier.admit inputs) and sigma = ok (Vol.normal 1.) in
  (match
     P.Bachelier.evaluate_many admitted Side.Call sigma
       P.
         [
           Request (Price, 0.); Request (Price, Float.nan); Request (Price, 1e-8);
         ]
   with
  | [
   P.Outcome (P.Price, Error P.Accuracy_exceeded);
   P.Outcome (P.Price, Error P.Invalid_accuracy);
   P.Outcome (P.Price, Ok c);
  ] ->
      (* Independent analytic value sigma sqrt(T)/(sqrt(2 pi)), broadly enclosed;
          acceptance is separately checked at zero and a finite requested bound. *)
      check "normal ATM independent value" (c.value > 0.398 && c.value < 0.399);
      check "normal ATM finite requested radius"
        (c.absolute_error > 0. && c.absolute_error <= 1e-8)
  | _ -> failwith "per-output limits and later success");
  let extreme = ok (P.Bachelier.admit { inputs with rate = -2048. }) in
  (match
     P.Bachelier.evaluate_many extreme Side.Call
       (ok (Vol.normal 0.))
       P.
         [
           Request (Price, 1e-8);
           Request (Delta, 1e-8);
           Request (Price, -1.);
           Request (Price, 1e-8);
         ]
   with
  | [
   P.Outcome (P.Price, Error P.Numerical_failure);
   P.Outcome (P.Delta, Error (P.Unsupported P.Zero_volatility_greek));
   P.Outcome (P.Price, Error P.Invalid_accuracy);
   P.Outcome (P.Price, Error P.Numerical_failure);
  ] ->
      ()
  | _ -> failwith "cached preparation failure preserves earlier checks");
  let expiry =
    ok (P.Bachelier.admit { inputs with forward = 5.; time_to_expiry = 0. })
  in
  (match
     P.Bachelier.evaluate_many expiry Side.Call sigma
       P.[ Request (Price, 0.); Request (Delta, 0.) ]
   with
  | [
   P.Outcome (P.Price, Ok c);
   P.Outcome (P.Delta, Error (P.Unsupported P.Expiry_greek));
  ] ->
      check "exact expiry mathematical payoff"
        (c.value = 5. && c.absolute_error = 0.)
  | _ -> failwith "expiry output semantics");
  let invalid = { inputs with forward = Float.nan } in
  check "empty invalid group"
    (Batch.evaluate_many Batch.Bachelier invalid Side.Call sigma [] = []);
  List.iter
    (fun (P.Outcome (_, result)) ->
      check "admission failure replicated"
        (match result with Error (P.Invalid_input _) -> true | _ -> false))
    (Batch.evaluate_many Batch.Bachelier invalid Side.Call sigma (requests ()));
  Bsm.run ();
  Black76.run ();
  Displaced.run ();
  Normal.run ();
  print_endline
    "shared preparation: four models, mixed failures, exact words, boundaries \
     and concurrent calls pass"
