type t
(** Independent real-model evaluation with explicit arithmetic enclosures.
    Original binary64 values and exact displaced sums are required. Failure
    raises [Enclosure.Unresolved]; a finite enclosure is not acceptance. *)

val black :
  spot:float ->
  spot_low:float ->
  strike:float ->
  strike_low:float ->
  time:float ->
  rate:float ->
  yield:float ->
  t

val normal : forward:float -> strike:float -> time:float -> rate:float -> t

val bounds : t -> Side.t -> Enclosure.t * Enclosure.t option
(** Discounted intrinsic and, for Black, the finite-volatility supremum. *)

val price : t -> Side.t -> float -> Enclosure.t
val pdf : Enclosure.t -> Enclosure.t
val cdf : Enclosure.t -> Enclosure.t
val pi : Enclosure.t
