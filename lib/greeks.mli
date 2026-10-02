(** First, second and mixed sensitivities of a European price.

    Time Greeks are [-d/dT / 365]: per calendar day, with remaining maturity
    decreasing. Volatility Greeks are per unit volatility in the model's own
    coordinate. Where the payoff has a kink (at the strike, at expiry or at zero
    variance) a spot or time derivative does not exist and is refused. *)

type why = Payoff_kink
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
  veta : Units.per_calendar_day Units.time_rate value;
  color : Units.per_calendar_day Units.time_rate value;
}

val kink : 'a value
val daily : float -> Units.per_calendar_day Units.time_rate value

val expiry :
  theta:float ->
  spot:float ->
  strike:float ->
  rate:float ->
  yield:float ->
  'coordinate t
(** The payoff's derivatives at [T = 0]: [theta] is +1 for a call, -1 for a put.
*)
