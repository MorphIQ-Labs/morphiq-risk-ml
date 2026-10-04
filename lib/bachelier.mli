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
