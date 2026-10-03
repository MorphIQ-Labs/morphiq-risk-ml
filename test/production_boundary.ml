open Morphiq_risk
module P = Production

let get = function Ok x -> x | Error _ -> failwith "unexpected refusal"
let require name yes = if not yes then failwith name

type 'c request = Request : ('c, 'a) P.quantity * 'a -> 'c request

(* Fixed before scoring: an explicit test request, not a production default or
   an economic materiality requirement. All values/Greeks have their own units. *)
let requests () =
  let e = 1e-10 in
  [
    Request (P.Price, e);
    Request (P.Delta, e);
    Request (P.Gamma, e);
    Request (P.Rho, e);
    Request (P.Theta, Units.time_rate e);
    Request (P.Charm, Units.time_rate e);
    Request (P.Color, Units.time_rate e);
    Request (P.Vega, Units.per_volatility e);
    Request (P.Vanna, Units.per_volatility e);
    Request (P.Volga, Units.per_volatility_squared e);
    Request (P.Veta, Units.volatility_time_rate e);
  ]

let count = ref 0

module Check (A : sig
  include P.MODEL

  val vol : float -> coordinate Vol.t
end) =
struct
  let interior inputs sigma =
    let admitted = get (A.admit inputs) and sigma = A.vol sigma in
    List.iter
      (fun side ->
        List.iter
          (fun (Request (quantity, limit)) ->
            ignore
              (get (A.evaluate admitted side sigma quantity ~max_error:limit));
            incr count)
          (requests ()))
      [ Side.Call; Side.Put ];
    List.iter
      (fun invalid ->
        require "nonfinite/negative accuracy refused"
          (A.evaluate admitted Side.Call sigma P.Price ~max_error:invalid
          = Error P.Invalid_accuracy))
      [ Float.nan; Float.infinity; Float.neg_infinity; -1. ];
    require "zero-volatility smooth Greek unsupported"
      (A.evaluate admitted Side.Call (A.vol 0.) P.Delta ~max_error:1e-10
      = Error (P.Unsupported P.Zero_volatility_greek));
    require "invalid IV quote is mathematical input refusal"
      (match A.implied admitted Side.Call (-1.) with
      | Error (P.Invalid_input _) -> true
      | _ -> false)
end

module Bsm = Check (struct
  include P.Bsm

  let vol s = get (Vol.lognormal s)
end)

module Black76 = Check (struct
  include P.Black76

  let vol s = get (Vol.lognormal s)
end)

module Displaced = Check (struct
  include P.Displaced

  let vol s = get (Vol.lognormal s)
end)

module Normal = Check (struct
  include P.Bachelier

  let vol s = get (Vol.normal s)
end)

let () =
  List.iter
    (fun s ->
      List.iter
        (fun t ->
          List.iter
            (fun r ->
              Bsm.interior
                {
                  spot = s;
                  strike = 100.;
                  time_to_expiry = t;
                  rate = r;
                  dividend_yield = 0.01;
                }
                0.2;
              Black76.interior
                { forward = s; strike = 100.; time_to_expiry = t; rate = r }
                0.2;
              Displaced.interior
                {
                  forward = s;
                  strike = 100.;
                  time_to_expiry = t;
                  rate = r;
                  displacement = 0.125;
                }
                0.2;
              Normal.interior
                { forward = s; strike = 100.; time_to_expiry = t; rate = r }
                5.)
            [ -0.05; 0.01; 0.05 ])
        [ 0.25; 1.; 4. ])
    [ 90.; 100.; 110. ];
  let normal inputs = get (P.Bachelier.admit inputs) in
  let sigma = get (Vol.normal 1.) in
  let p a limit =
    P.Bachelier.evaluate a Side.Call sigma P.Price ~max_error:limit
  in
  let expiry =
    normal { forward = -1.; strike = -2.; time_to_expiry = 0.; rate = 0. }
  in
  let exact = get (p expiry 0.) in
  require "expiry exact payoff certificate"
    (exact.value = 1. && exact.absolute_error = 0.);
  require "expiry Greek unsupported"
    (P.Bachelier.evaluate expiry Side.Call sigma P.Delta ~max_error:1e-10
    = Error (P.Unsupported P.Expiry_greek));
  require "expiry IV class retained"
    (P.Bachelier.implied expiry Side.Call 1. = Ok Iv.Not_identifiable_at_expiry);
  let shifted_expiry =
    get
      (P.Displaced.admit
         {
           forward = -1.;
           strike = -2.;
           displacement = 0.;
           time_to_expiry = 0.;
           rate = 0.;
         })
  in
  require "expiry does not impose live shifted positivity"
    ((get
        (P.Displaced.evaluate shifted_expiry Side.Call
           (get (Vol.lognormal 0.))
           P.Price ~max_error:0.))
       .value = 1.);
  require "nonfinite market input rejected by original owner"
    (match
       P.Bachelier.admit
         { forward = Float.nan; strike = 0.; time_to_expiry = 1.; rate = 0. }
     with
    | Error (P.Invalid_input _) -> true
    | _ -> false);
  let overflow =
    normal
      {
        forward = Float.max_float;
        strike = -.Float.max_float;
        time_to_expiry = 1.;
        rate = 0.;
      }
  in
  require "finite mathematical inputs can fail arithmetic capability"
    (p overflow Float.max_float = Error P.Numerical_failure);
  List.iter
    (fun rate ->
      let beyond =
        normal { forward = 0.; strike = 0.; time_to_expiry = 1.; rate }
      in
      require "exponential guard failure"
        (p beyond Float.max_float = Error P.Numerical_failure))
    [ -2048.; 2048. ];
  List.iter
    (fun rate ->
      let within =
        normal { forward = 0.; strike = 0.; time_to_expiry = 1.; rate }
      in
      ignore (get (p within Float.max_float)))
    [ -512.; 512. ];
  let joint =
    normal
      { forward = 0.; strike = 0.; time_to_expiry = 1. /. 4096.; rate = 2048. }
  in
  ignore (get (p joint 1e-10));
  let atm =
    normal { forward = 0.; strike = 0.; time_to_expiry = 1.; rate = 0. }
  in
  let zero =
    get
      (P.Bachelier.evaluate atm Side.Call
         (get (Vol.normal 0.))
         P.Price ~max_error:0.)
  in
  require "zero-variance exact price"
    (zero.value = 0. && zero.absolute_error = 0.);
  require "zero requested error does not accept a nonexact result"
    (p atm 0. = Error P.Accuracy_exceeded);
  let tiny =
    normal { forward = 0.; strike = 0.; time_to_expiry = 1.; rate = 700. }
  in
  let tail = get (p tiny 1e-10) in
  require "tiny value retains a finite absolute bound"
    (Float.is_finite tail.absolute_error && tail.absolute_error >= 0.);
  Printf.printf
    "%d interior quantity requests; admission, accuracy, expiry, \
     zero-variance, tail and joint capability controls pass\n"
    !count
