(** Double-double arithmetic: [hi + lo] with [|lo| <= ulp(hi)/2], about 106
    bits (Dekker 1971; Hida, Li and Bailey). *)

type t = { hi : float; lo : float }

val of_float : float -> t
val to_float : t -> float
val add : t -> t -> t
val sub : t -> t -> t
val neg : t -> t
val mul : t -> t -> t
val mul_float : t -> float -> t
val div : t -> t -> t
val two_prod : float -> float -> t
val scale : t -> int -> t
val compare_float : t -> float -> int

val ln2 : t

val log_float : float -> t
(** [ln a] for positive, finite [a]. *)

val exp : t -> t
val expm1 : t -> t

val to_float_scaled : t -> int -> float
(** [2^k (hi + lo)] rounded once, including into the subnormals. *)
