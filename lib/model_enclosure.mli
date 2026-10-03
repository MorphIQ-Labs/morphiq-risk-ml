module type S = sig
  type scalar

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

  val bounds : t -> Side.t -> scalar * scalar option
  (** Discounted intrinsic and, for Black, the finite-volatility supremum. *)

  val price : t -> Side.t -> float -> scalar

  val price_enclosed : t -> Side.t -> scalar -> scalar
  (** Also accepts exact two-word volatility midpoints for IV rounding
      decisions. *)

  val pdf : scalar -> scalar
  val cdf : scalar -> scalar
  val pi : scalar

  val inverse_residual : t -> Side.t -> float -> scalar -> scalar
  (** Enclose [price / quote - 1] directly for a positive quote, including tail
      prefactors before exponentiation. For quote zero, enclose price itself. *)
end

include S with type scalar = Enclosure.t
module Fast : S with type scalar = Enclosure.Fast.t
