val evaluate :
  spot:float ->
  spot_low:float ->
  strike:float ->
  strike_low:float ->
  time:float ->
  rate:float ->
  yield:float ->
  Side.t ->
  float ->
  float Greeks.value
(** Original-input BSM rate derivative, with a complete binary64 rounding-cell
    proof or explicit numerical failure. Requires admitted positive maturity,
    positive exact spot/strike and nonnegative volatility. *)
