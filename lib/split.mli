(** Error-free transformations, and an exponential with an exactly split
    argument. *)

val two_sum : float -> float -> float * float
(** [two_sum a b = (s, e)] with [a + b = s + e] exactly (Knuth). *)

val square : float -> float * float
(** [square u = (hi, lo)] with [u^2 = hi + lo] exactly. *)

val ln2_hi : float
val ln2_lo : float

val scaled_exp_neg : ?k:int -> float -> float -> float -> float
(** [scaled_exp_neg ~k m hi lo] is [2^k m e^(-(hi + lo))] for [hi >= 0],
    [|lo| <= ulp(hi)]. The exponential is applied last, through a Cody-Waite
    reduction, so the result neither under- nor overflows before the end. *)

val sqrt : float -> float * float
(** [sqrt t = (hi, lo)] with [hi + lo = sqrt t] to about 106 bits. *)

val quotient_dd : float -> float -> float -> float -> float * float
(** [quotient_dd n nl d dl] is [(n + nl)/(d + dl)] as [hi + lo], to first order.
*)

val quotient : float -> float -> float * float
(** [quotient n d = (q, r)] with [n/d = q + r] to first order. *)

val product_ldexp : float list -> int -> float
(** [product_ldexp fs k] is [2^k] times the product of [fs], rounded once. *)
