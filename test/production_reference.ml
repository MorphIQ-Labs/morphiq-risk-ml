open Morphiq_risk
module P = Production

let power2 n =
  if n >= 0 then Q.of_bigint (Z.shift_left Z.one n)
  else Q.make Z.one (Z.shift_left Z.one (-n))

let count = ref 0
let limit_checks = ref 0

let get = function
  | Ok x -> x
  | Error _ -> failwith "unexpected production refusal"

module Check (A : sig
  include P.MODEL

  val vol : float -> coordinate Vol.t
end) =
struct
  let run admitted side sigma name reference uncertainty =
    let sigma = A.vol sigma in
    let check quantity wrap unwrap =
      let result =
        get
          (A.evaluate admitted side sigma quantity
             ~max_error:(wrap Float.max_float))
      in
      let got = unwrap result.P.value
      and bound = unwrap result.absolute_error in
      if not (Float.is_finite got && Float.is_finite bound && bound >= 0.) then
        failwith "nonfinite production certificate";
      let error = Q.abs (Q.sub (Q.of_float got) reference) in
      if Q.compare error (Q.add (Q.of_float bound) uncertainty) > 0 then
        failwith ("public production bound misses reference: " ^ name);
      (* The same request must accept its proved limit, and refuse a smaller
         limit. This is an acceptance-boundary test, not a fitted tolerance. *)
      ignore
        (get (A.evaluate admitted side sigma quantity ~max_error:(wrap bound)));
      if bound > 0. then (
        if
          A.evaluate admitted side sigma quantity
            ~max_error:(wrap (Float.pred bound))
          <> Error P.Accuracy_exceeded
        then failwith "accuracy limit not enforced";
        incr limit_checks);
      incr count
    in
    match name with
    | "price" -> check P.Price Fun.id Fun.id
    | "delta" -> check P.Delta Fun.id Fun.id
    | "gamma" -> check P.Gamma Fun.id Fun.id
    | "rho" -> check P.Rho Fun.id Fun.id
    | "theta" -> check P.Theta Units.time_rate (fun x -> (x :> float))
    | "charm" -> check P.Charm Units.time_rate (fun x -> (x :> float))
    | "color" -> check P.Color Units.time_rate (fun x -> (x :> float))
    | "vega" -> check P.Vega Units.per_volatility (fun x -> (x :> float))
    | "vanna" -> check P.Vanna Units.per_volatility (fun x -> (x :> float))
    | "volga" ->
        check P.Volga Units.per_volatility_squared (fun x -> (x :> float))
    | "veta" -> check P.Veta Units.volatility_time_rate (fun x -> (x :> float))
    | _ -> invalid_arg name
end

module Bsm = Check (struct
  include P.Bsm

  let vol s = Result.get_ok (Vol.lognormal s)
end)

module Black76 = Check (struct
  include P.Black76

  let vol s = Result.get_ok (Vol.lognormal s)
end)

module Displaced = Check (struct
  include P.Displaced

  let vol s = Result.get_ok (Vol.lognormal s)
end)

module Bachelier = Check (struct
  include P.Bachelier

  let vol s = Result.get_ok (Vol.normal s)
end)

let row is_price model side name s k t r q sigma shift exponent h l tail =
  let f = Int64.float_of_bits in
  let s, k, t, r, q, sigma, shift =
    (f s, f k, f t, f r, f q, f sigma, f shift)
  in
  let name = if is_price then "price" else name in
  let side = if side = "call" then Side.Call else Side.Put in
  let factor = power2 exponent in
  let reference =
    Q.mul factor
      (List.fold_left
         (fun a x -> Q.add a (Q.of_float (f x)))
         Q.zero [ h; l; tail ])
  in
  let uncertainty = Q.mul factor (power2 (-158)) in
  match model with
  | "bsm" ->
      Bsm.run
        (get
           (P.Bsm.admit
              {
                spot = s;
                strike = k;
                time_to_expiry = t;
                rate = r;
                dividend_yield = q;
              }))
        side sigma name reference uncertainty
  | "black76" ->
      Black76.run
        (get
           (P.Black76.admit
              { forward = s; strike = k; time_to_expiry = t; rate = r }))
        side sigma name reference uncertainty
  | "displaced" ->
      Displaced.run
        (get
           (P.Displaced.admit
              {
                forward = s;
                strike = k;
                displacement = shift;
                time_to_expiry = t;
                rate = r;
              }))
        side sigma name reference uncertainty
  | "bachelier" ->
      Bachelier.run
        (get
           (P.Bachelier.admit
              { forward = s; strike = k; time_to_expiry = t; rate = r }))
        side sigma name reference uncertainty
  | _ -> invalid_arg model

let () =
  List.iteri
    (fun i path ->
      Oracle_fixture.lines ~columns:[ 14 ]
        ~names:[ "greek_bits"; "model_enclosures" ]
        path
      |> List.iter (fun line ->
             if line <> "" && line.[0] <> '#' then
               Scanf.sscanf line
                 "%s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
                 (row (i = 1))))
    [ Sys.argv.(1); Sys.argv.(2) ];
  Printf.printf
    "%d public price/Greek certificates; %d exact acceptance-limit controls\n"
    !count !limit_checks;
  if !count = 0 || !limit_checks = 0 then failwith "empty production coverage"
