type unsupported = Expiry_greek | Zero_volatility_greek

type error =
  | Invalid_input of Refusal.t
  | Invalid_accuracy
  | Unsupported of unsupported
  | Numerical_failure
  | Accuracy_exceeded
      (** No failed request contains a usable fallback value. Invalid accuracy
          means a nonfinite or negative limit. Arithmetic capability and an
          unmet requested limit are distinct from mathematical admission and
          unsupported derivatives. *)

type 'a certified = { value : 'a; absolute_error : 'a }
(** Finite value and finite nonnegative outward absolute error for the exact
    real model quantity. The bound meets the requested limit in the same units.
    The certificate does not include model, market-data or aggregation error. *)

type ('coordinate, 'value) quantity =
  | Price : ('c, float) quantity
  | Delta : ('c, float) quantity
  | Gamma : ('c, float) quantity
  | Theta : ('c, Units.per_calendar_day Units.time_rate) quantity
  | Vega : ('c, 'c Units.per_volatility) quantity
  | Rho : ('c, float) quantity
  | Vanna : ('c, 'c Units.per_volatility) quantity
  | Volga : ('c, 'c Units.per_volatility_squared) quantity
  | Charm : ('c, Units.per_calendar_day Units.time_rate) quantity
  | Veta :
      ('c, (Units.per_calendar_day, 'c) Units.volatility_time_rate) quantity
  | Color : ('c, Units.per_calendar_day Units.time_rate) quantity

module type MODEL = sig
  type inputs
  type coordinate
  type admitted

  val admit : inputs -> (admitted, error) result
  (** Delegate mathematical validation to the existing model owner. Admission
      does not promise success for every output or requested accuracy. *)

  val evaluate :
    admitted ->
    Side.t ->
    coordinate Vol.t ->
    (coordinate, 'a) quantity ->
    max_error:'a ->
    ('a certified, error) result
  (** Require an explicit finite, nonnegative absolute limit before evaluation.
      Price covers expiry/zero variance when its enclosure resolves. Smooth
      Greeks require strictly positive maturity and volatility. Any intermediate
      violating the enclosure's joint arithmetic preconditions fails explicitly.
      There is no empirical default tolerance or fallback to the fast API. *)

  val implied : admitted -> Side.t -> float -> (coordinate Iv.t, error) result
  (** Preserve the public certified-IV contract and all mathematical and
      computational outcomes. Positive roots require nearest-even rounding; no
      caller-specified weaker tolerance is substituted. *)
end

module E = Enclosure
module M = Model_enclosure

type descriptor =
  | Expiry of { spot : float; strike : float }
  | Live of { model : Adaptive_iv.model; rho_forward : bool }

let number : type c a. (c, a) quantity -> a -> float =
 fun quantity value ->
  match quantity with
  | Price -> value
  | Delta -> value
  | Gamma -> value
  | Rho -> value
  | Theta -> (value :> float)
  | Charm -> (value :> float)
  | Color -> (value :> float)
  | Vega -> (value :> float)
  | Vanna -> (value :> float)
  | Volga -> (value :> float)
  | Veta -> (value :> float)

let label : type c a. (c, a) quantity -> float -> a =
 fun quantity value ->
  match quantity with
  | Price -> value
  | Delta -> value
  | Gamma -> value
  | Rho -> value
  | Theta -> Units.time_rate value
  | Charm -> Units.time_rate value
  | Color -> Units.time_rate value
  | Vega -> Units.per_volatility value
  | Vanna -> Units.per_volatility value
  | Volga -> Units.per_volatility_squared value
  | Veta -> Units.volatility_time_rate value

let sensitivity : type c a. (c, a) quantity -> M.sensitivity option = function
  | Price -> None
  | Delta -> Some M.Delta
  | Gamma -> Some M.Gamma
  | Theta -> Some M.Theta
  | Vega -> Some M.Vega
  | Rho -> Some M.Rho
  | Vanna -> Some M.Vanna
  | Volga -> Some M.Volga
  | Charm -> Some M.Charm
  | Veta -> Some M.Veta
  | Color -> Some M.Color

let prepare = function
  | Adaptive_iv.Black c ->
      M.black ~spot:c.spot ~spot_low:c.spot_low ~strike:c.strike
        ~strike_low:c.strike_low ~time:c.time ~rate:c.rate ~yield:c.yield
  | Adaptive_iv.Normal c ->
      M.normal ~forward:c.forward ~strike:c.strike ~time:c.time ~rate:c.rate

let black_descriptor = function
  | Black.Coordinates.Expiry c -> Expiry { spot = c.spot; strike = c.strike }
  | Black.Coordinates.Live c ->
      Live
        {
          model =
            Adaptive_iv.Black
              {
                spot = c.original_spot;
                spot_low = c.original_spot_low;
                strike = c.original_strike;
                strike_low = c.original_strike_low;
                time = c.time;
                rate = c.rate;
                yield = c.yield;
              };
          rho_forward = c.tied;
        }

module type SOURCE = sig
  type inputs
  type admitted
  type coordinate

  val admit : inputs -> (admitted, Refusal.t) result
  val descriptor : inputs -> admitted -> descriptor

  val implied :
    admitted -> Side.t -> float -> (coordinate Iv.t, Refusal.t) result
end

module Make (Source : SOURCE) = struct
  type inputs = Source.inputs
  type coordinate = Source.coordinate
  type admitted = { source : Source.admitted; descriptor : descriptor }

  let admit inputs =
    match Source.admit inputs with
    | Error e -> Error (Invalid_input e)
    | Ok source -> Ok { source; descriptor = Source.descriptor inputs source }

  let evaluate (type a) admitted side sigma
      (quantity : (coordinate, a) quantity) ~(max_error : a) =
    let limit = number quantity max_error in
    if not (Float.is_finite limit && limit >= 0.) then Error Invalid_accuracy
    else
      let sigma = Vol.to_float sigma in
      let requested = sensitivity quantity in
      match (admitted.descriptor, requested) with
      | Expiry _, Some _ -> Error (Unsupported Expiry_greek)
      | Live _, Some _ when sigma = 0. ->
          Error (Unsupported Zero_volatility_greek)
      | _ -> (
          try
            let enclosed =
              match admitted.descriptor with
              | Expiry c -> (
                  let payoff =
                    E.mul_float
                      (E.sub (E.exact c.spot) (E.exact c.strike))
                      (Side.sign side)
                  in
                  match E.sign payoff with
                  | E.Positive -> payoff
                  | E.Negative | E.Zero -> E.exact 0.
                  | E.Indeterminate -> raise (E.Unresolved "expiry payoff sign")
                  )
              | Live c -> (
                  let model = prepare c.model in
                  match requested with
                  | None -> M.price model side sigma
                  | Some greek ->
                      M.greek model side sigma ~rho_forward:c.rho_forward greek)
            in
            let value = enclosed.hi in
            let absolute_error = E.error_of_float enclosed value in
            if
              not
                (Float.is_finite value
                && Float.is_finite absolute_error
                && absolute_error >= 0.)
            then Error Numerical_failure
            else if absolute_error > limit then Error Accuracy_exceeded
            else
              Ok
                {
                  value = label quantity value;
                  absolute_error = label quantity absolute_error;
                }
          with E.Unresolved _ -> Error Numerical_failure)

  let implied admitted side quote =
    Result.map_error
      (fun e -> Invalid_input e)
      (Source.implied admitted.source side quote)
end

module Black_source (Model : Black.MODEL) = struct
  type inputs = Model.inputs
  type admitted = Model.admitted
  type coordinate = Vol.lognormal

  let admit = Model.admit
  let implied = Model.implied
  let descriptor _ admitted = black_descriptor (Model.coordinates admitted)
end

module Bsm = Make (Black_source (Black.Bsm))
module Black76 = Make (Black_source (Black.Black76))
module Displaced = Make (Black_source (Black.Displaced))

module Bachelier = Make (struct
  type inputs = Bachelier.inputs
  type admitted = Bachelier.admitted
  type coordinate = Vol.normal

  let admit = Bachelier.admit
  let implied = Bachelier.implied

  let descriptor (i : inputs) _ =
    if i.time_to_expiry = 0. then Expiry { spot = i.forward; strike = i.strike }
    else
      Live
        {
          model =
            Adaptive_iv.Normal
              {
                forward = i.forward;
                strike = i.strike;
                time = i.time_to_expiry;
                rate = i.rate;
              };
          rho_forward = true;
        }
end)
