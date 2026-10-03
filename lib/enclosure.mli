(** Runtime arithmetic enclosures from IEEE residuals and explicit analytic
    remainders. See docs/runtime-enclosures.md. This module is an internal
    building block, not production qualification of financial outputs. *)

exception Unresolved of string

type t = private { hi : float; lo : float; error : float }
(** The real value is within [error] of the unevaluated sum [hi+lo]. All fields
    are finite and [error] is nonnegative. *)

type sign = Negative | Zero | Positive | Indeterminate

val exact : float -> t
val of_words : float -> float -> t
val add : t -> t -> t
val sub : t -> t -> t
val neg : t -> t
val mul : t -> t -> t
val mul_float : t -> float -> t
val div : t -> t -> t
val div_float : t -> float -> t
val scale : t -> int -> t
val sqrt : t -> t
val exp : t -> t
val expm1 : t -> t
val log : t -> t
val magnitude : t -> float
val sign : t -> sign
val compare_float : t -> float -> sign
val error_of_float : t -> float -> float

val add_error : t -> float -> t
(** Enlarge a radius by a proved nonnegative error allowance. *)
