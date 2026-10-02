(** Double-double arithmetic: [hi + lo] with [hi = RN(hi + lo)]. The primitives
    are the published algorithms with proved relative error bounds (u = 2^-53,
    no underflow or overflow): [add] 3u^2 + 13u^3, [add_float] 2u^2, [mul_float]
    2u^2, [mul] 5u^2, [div] 9.8u^2 (Joldes, Muller and Popescu, ACM TOMS 2017),
    [sqrt] 25/8 u^2 (Lefèvre, Louvet, Muller, Picot and Rideau, ACM TOMS 2023).
    [two_prod] is exact. *)

type t = { hi : float; lo : float }

val of_float : float -> t
val to_float : t -> float
val add : t -> t -> t
val sub : t -> t -> t
val neg : t -> t
val mul : t -> t -> t
val add_float : t -> float -> t
val mul_float : t -> float -> t
val div : t -> t -> t
val two_prod : float -> float -> t
val scale : t -> int -> t
val compare_float : t -> float -> int
val ln2 : t

val log_float : float -> t
(** [ln a] for positive, finite [a]. *)

val sqrt : t -> t
val exp : t -> t
val expm1 : t -> t

val to_float_scaled : t -> int -> float
(** [2^k (hi + lo)] rounded once, including into the subnormals. *)
