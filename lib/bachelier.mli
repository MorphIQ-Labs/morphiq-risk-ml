(** European options under the normal (Bachelier) model.

    Fast Greek results are checked per field for finiteness in their output
    units. Unresolved arithmetic returns [Greeks.Numerical_failure]; a finite
    result retains the documented checked-input accuracy scope. *)

type inputs = {
  forward : float;
  strike : float;
  time_to_expiry : float;
  rate : float;
}

type admitted
(** Inputs that passed the domain check. Only {!admit} constructs one. *)

val admit : inputs -> (admitted, Refusal.t) result
(** Forward and strike may take any finite sign. *)

val price : admitted -> Side.t -> Vol.normal Vol.t -> float

val implied : admitted -> Side.t -> float -> (Vol.normal Iv.t, Refusal.t) result
(** A correctly rounded positive inverse, a mathematical classification, or an
    explicit computational failure; see {!Iv.t}. *)

val greeks : admitted -> Side.t -> Vol.normal Vol.t -> Vol.normal Greeks.t

(** Internal bounded OTM preparation; exposed only through [Internal] by the
    primary public interface. A failed selection means scalar fallback, not
    mathematical refusal. Parameters are immutable and retain the original
    operation graph, including the quotient residual. *)
module Fast_middle : sig
  type t = private { q : float; low : float; s : float; discount : float }

  val may_prepare : inputs -> Side.t -> Vol.normal Vol.t -> bool
  (** Performance hint on rounded coordinates, not admission or selection.
      Always use [prepare] before executing the bounded operation graph. *)

  val prepare : admitted -> Side.t -> Vol.normal Vol.t -> t option
  val price : t -> float
end
