(** European options under the normal (Bachelier) model. *)

type inputs = { forward : float; strike : float; time_to_expiry : float; rate : float }

type admitted
(** Inputs that passed the domain check. Only {!admit} constructs one. *)

val admit : inputs -> (admitted, Refusal.t) result
(** Forward and strike may take any finite sign. *)

val price : admitted -> Side.t -> Vol.normal Vol.t -> float
