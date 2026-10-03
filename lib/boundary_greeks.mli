val veta :
  weight:float ->
  weight_low:float ->
  rate:float ->
  time:float ->
  float Greeks.value
(** Zero-volatility ATM mixed derivative. Preconditions: positive maturity, a
    proved ATM identity throughout a maturity neighbourhood, and exact
    [weight + weight_low]. Unresolved arithmetic or rounding is a numerical
    failure, not a payoff kink. *)
