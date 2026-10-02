(** European options under the normal (Bachelier) model. *)

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
(** The normal volatility whose price is the quote, or why there is none. *)

val greeks : admitted -> Side.t -> Vol.normal Vol.t -> Vol.normal Greeks.t
