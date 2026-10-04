(* Protocol adapter only: independent reference calculations live in Python.
   Every response binds the complete original request, including failures. *)
open Morphiq_risk
module P = Production

type outcome =
  | Class of string
  | Value of float
  | Certificate of float * float
  | Root of float

let invalid _ = Class "invalid_input"

let greek = function
  | Ok x -> Value x
  | Error Greeks.Payoff_kink -> Class "payoff_kink"
  | Error Greeks.Numerical_failure -> Class "numerical_failure"

let iv = function
  | Iv.Root x -> Root (Vol.to_float x)
  | Iv.Below_intrinsic -> Class "below_intrinsic"
  | Iv.Above_maximum -> Class "above_maximum"
  | Iv.Not_identifiable_at_expiry -> Class "expiry"
  | Iv.Below_smallest_volatility -> Class "below_smallest"
  | Iv.Non_convergence -> Class "non_convergence"
  | Iv.Numerical_failure -> Class "numerical_failure"

let production_error = function
  | P.Invalid_input _ -> Class "invalid_input"
  | P.Invalid_accuracy -> Class "invalid_accuracy"
  | P.Unsupported P.Expiry_greek -> Class "unsupported_expiry"
  | P.Unsupported P.Zero_volatility_greek -> Class "unsupported_zero_variance"
  | P.Numerical_failure -> Class "numerical_failure"
  | P.Accuracy_exceeded -> Class "accuracy_exceeded"

module type Fast = sig
  type inputs
  type admitted
  type coordinate

  val admit : inputs -> (admitted, Refusal.t) result
  val price : admitted -> Side.t -> coordinate Vol.t -> float
  val greeks : admitted -> Side.t -> coordinate Vol.t -> coordinate Greeks.t

  val implied :
    admitted -> Side.t -> float -> (coordinate Iv.t, Refusal.t) result

  val vol : float -> (coordinate Vol.t, Refusal.t) result
end

module Run
    (F : Fast)
    (A : P.MODEL with type inputs = F.inputs and type coordinate = F.coordinate) =
struct
  let production a side sigma name limit =
    let evaluate quantity wrap unwrap =
      match A.evaluate a side sigma quantity ~max_error:(wrap limit) with
      | Error e -> production_error e
      | Ok certificate ->
          Certificate
            (unwrap certificate.P.value, unwrap certificate.absolute_error)
    in
    match name with
    | "price" -> evaluate P.Price Fun.id Fun.id
    | "delta" -> evaluate P.Delta Fun.id Fun.id
    | "gamma" -> evaluate P.Gamma Fun.id Fun.id
    | "rho" -> evaluate P.Rho Fun.id Fun.id
    | "theta" -> evaluate P.Theta Units.time_rate (fun x -> (x :> float))
    | "charm" -> evaluate P.Charm Units.time_rate (fun x -> (x :> float))
    | "color" -> evaluate P.Color Units.time_rate (fun x -> (x :> float))
    | "vega" -> evaluate P.Vega Units.per_volatility (fun x -> (x :> float))
    | "vanna" -> evaluate P.Vanna Units.per_volatility (fun x -> (x :> float))
    | "volga" ->
        evaluate P.Volga Units.per_volatility_squared (fun x -> (x :> float))
    | "veta" ->
        evaluate P.Veta Units.volatility_time_rate (fun x -> (x :> float))
    | _ -> invalid_arg "quantity"

  let run mode name inputs side sigma quote limit =
    if mode = "production" then
      match A.admit inputs with
      | Error e -> production_error e
      | Ok a -> (
          if name = "iv" then
            match A.implied a side quote with
            | Ok x -> iv x
            | Error e -> production_error e
          else
            match F.vol sigma with
            | Error e -> invalid e
            | Ok v -> production a side v name limit)
    else
      match F.admit inputs with
      | Error e -> invalid e
      | Ok a -> (
          if mode = "iv" then
            match F.implied a side quote with
            | Ok x -> iv x
            | Error e -> invalid e
          else
            match F.vol sigma with
            | Error e -> invalid e
            | Ok v ->
                if name = "price" then Value (F.price a side v)
                else greek (Greek_values.pick (F.greeks a side v) name))
end

module Bsm =
  Run
    (struct
      include Black.Bsm

      type coordinate = Vol.lognormal

      let vol = Vol.lognormal
    end)
    (P.Bsm)

module Black76 =
  Run
    (struct
      include Black.Black76

      type coordinate = Vol.lognormal

      let vol = Vol.lognormal
    end)
    (P.Black76)

module Displaced =
  Run
    (struct
      include Black.Displaced

      type coordinate = Vol.lognormal

      let vol = Vol.lognormal
    end)
    (P.Displaced)

module Normal =
  Run
    (struct
      include Bachelier

      type coordinate = Vol.normal

      let vol = Vol.normal
    end)
    (P.Bachelier)

let primitive mode s k =
  let module E = Internal.Enclosure in
  let module C = Internal.Certified_iv in
  try
    if mode = "enclosure" then
      let x = E.of_words s k in
      Certificate (x.hi, E.error_of_float x x.hi)
    else
      let midpoint =
        E.add (E.mul_float (E.exact s) 0.5) (E.mul_float (E.exact k) 0.5)
      in
      match
        C.solve
          ~prepare_residual:(fun () -> fun x -> E.sub x midpoint)
          ~intrinsic:(E.sub (E.exact 2.) midpoint)
          ~maximum:None ~quote:2. ~proposal:k ()
      with
      | C.Root x -> Root x
      | C.Numerical_failure -> Class "numerical_failure"
      | C.Non_convergence -> Class "non_convergence"
      | _ -> Class "unexpected_solver_class"
  with E.Unresolved _ -> Class "numerical_failure"

let evaluate line =
  Scanf.sscanf line "%s %s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
    (fun id mode model side name sb kb tb rb qb vb db pb lb ->
      let f = Int64.float_of_bits in
      let s, k, t, r, q, sigma, shift, quote, limit =
        (f sb, f kb, f tb, f rb, f qb, f vb, f db, f pb, f lb)
      in
      let side =
        match side with
        | "call" -> Side.Call
        | "put" -> Side.Put
        | _ -> invalid_arg "side"
      in
      let result =
        match model with
        | "bsm" ->
            Bsm.run mode name
              {
                spot = s;
                strike = k;
                time_to_expiry = t;
                rate = r;
                dividend_yield = q;
              }
              side sigma quote limit
        | "black76" ->
            Black76.run mode name
              { forward = s; strike = k; time_to_expiry = t; rate = r }
              side sigma quote limit
        | "displaced" ->
            Displaced.run mode name
              {
                forward = s;
                strike = k;
                time_to_expiry = t;
                rate = r;
                displacement = shift;
              }
              side sigma quote limit
        | "bachelier" ->
            Normal.run mode name
              { forward = s; strike = k; time_to_expiry = t; rate = r }
              side sigma quote limit
        | "primitive" -> primitive mode s k
        | _ -> invalid_arg "model"
      in
      (id, result))

let () =
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--budgets" then (
    List.iter
      (fun (key, budget) -> Printf.printf "%s %.0f\n" key budget)
      Budget_greeks.values;
    List.iter
      (fun family ->
        Printf.printf "%s price %.0f\n" family
          (Bounds.price_ulp_budget_max family))
      [ "black"; "bachelier" ];
    exit 0);
  let lines = In_channel.with_open_text Sys.argv.(1) In_channel.input_lines in
  if lines = [] || List.length lines > 50000 then invalid_arg "request count";
  List.iter
    (fun line ->
      let id, result = evaluate line in
      let digest = Digest.BLAKE256.to_hex (Digest.BLAKE256.string line) in
      let status, value, radius =
        match result with
        | Class name -> (name, "-", "-")
        | Value x ->
            ("value", Printf.sprintf "%016Lx" (Int64.bits_of_float x), "-")
        | Root x ->
            ("root", Printf.sprintf "%016Lx" (Int64.bits_of_float x), "-")
        | Certificate (x, e) ->
            ( "certificate",
              Printf.sprintf "%016Lx" (Int64.bits_of_float x),
              Printf.sprintf "%016Lx" (Int64.bits_of_float e) )
      in
      Printf.printf "%s %s %s %s %s\n%!" id digest status value radius)
    lines
