(** Enforced per-request numerical acceptance for the scalar European slice.
    Intended use and exclusions: [docs/production-boundary-design.md]. This API
    is a candidate capability, not institutional deployment approval. *)

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

type 'a certified = private { value : 'a; absolute_error : 'a }
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

type 'c request =
  | Request : ('c, 'a) quantity * 'a -> 'c request
      (** One requested quantity with its absolute error limit in the same
          units. *)

type 'c outcome =
  | Outcome : ('c, 'a) quantity * ('a certified, error) result -> 'c outcome
      (** One typed result for each request, in order, including
          duplicates/errors. *)

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

module type MULTI_OUTPUT_MODEL = sig
  include MODEL

  val evaluate_many :
    admitted ->
    Side.t ->
    coordinate Vol.t ->
    coordinate request list ->
    coordinate outcome list
  (** Equivalent to ordered scalar evaluations with a separate limit and result
      per entry. Reuses immutable model preparation within this call only. Empty
      lists return empty lists. A failure never suppresses later outputs;
      concurrent calls on the same admitted model share no mutable scratch. *)
end

module Bsm :
  MULTI_OUTPUT_MODEL
    with type inputs = Black.Bsm.inputs
     and type coordinate = Vol.lognormal

module Black76 :
  MULTI_OUTPUT_MODEL
    with type inputs = Black.Black76.inputs
     and type coordinate = Vol.lognormal

module Displaced :
  MULTI_OUTPUT_MODEL
    with type inputs = Black.Displaced.inputs
     and type coordinate = Vol.lognormal

module Bachelier :
  MULTI_OUTPUT_MODEL
    with type inputs = Bachelier.inputs
     and type coordinate = Vol.normal
