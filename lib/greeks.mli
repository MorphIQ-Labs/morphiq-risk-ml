(** First, second and mixed sensitivities of a European price.

    Time Greeks are [-d/dT / 365]: per calendar day, with remaining maturity
    decreasing. Volatility Greeks are per unit volatility in the model's own
    coordinate. Kinks are specific to the varied coordinate. At positive
    maturity and zero-volatility ATM, forward rho/theta are zero and the time
    derivative of right vega exists; spot derivatives remain undefined. *)

type why =
  | Payoff_kink
  | Numerical_failure
      (** [Payoff_kink] means the requested derivative is undefined.
          [Numerical_failure] means arithmetic could not produce a finite result
          in that field's output units, its coordinate was unresolved, or its
          required boundary enclosure could not establish a rounded result. It
          is not a usable approximate value. A finite fast Greek retains its
          documented checked-input assurance; finite acceptance alone is not an
          accuracy certificate. *)

type 'a value = ('a, why) result

type 'coordinate t = {
  delta : float value;
  gamma : float value;
  theta : Units.per_calendar_day Units.time_rate value;
  vega : 'coordinate Units.per_volatility value;
  rho : float value;
  vanna : 'coordinate Units.per_volatility value;
  volga : 'coordinate Units.per_volatility_squared value;
  charm : Units.per_calendar_day Units.time_rate value;
  veta : (Units.per_calendar_day, 'coordinate) Units.volatility_time_rate value;
  color : Units.per_calendar_day Units.time_rate value;
}

val ensure_finite : 'coordinate t -> 'coordinate t
(** Replace each nonfinite [Ok] payload with [Error Numerical_failure]. Preserve
    finite payload bits, units, coordinates and existing errors. This is output
    validation, not model admission or an accuracy certificate. *)

val kink : 'a value
val daily : float -> Units.per_calendar_day Units.time_rate value

val daily_volatility :
  float ->
  (Units.per_calendar_day, 'coordinate) Units.volatility_time_rate value
(** Convert a caller-established annual mixed time/volatility sensitivity to
    per-calendar-day units. This helper does not validate its raw input. *)

val expiry :
  theta:float ->
  spot:float ->
  strike:float ->
  rate:float ->
  yield:float ->
  'coordinate t
(** The payoff's derivatives at [T = 0]: [theta] is +1 for a call, -1 for a put.
*)
