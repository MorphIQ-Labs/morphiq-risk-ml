(** Runtime enclosures; fixed work configurations share the same proved residual
    and remainder identities. Neither is production qualification. *)
module type S = sig
  exception Unresolved of string

  type t = private {
    hi : float;
    lo : float;
    third : float;
    fourth : float;
    error : float;
  }
  (** The real value is within [error] of the unevaluated sum of [words]. All
      fields are finite and [error] is nonnegative. The zero-eliminated lower
      words occupy [third] and [fourth]; zero means an absent trailing word.
      [words] preserves the logical expansion including the first two slots. *)

  type sign = Negative | Zero | Positive | Indeterminate

  val exact : float -> t
  val of_words : float -> float -> t
  val words : t -> float list

  val centre : t -> t
  (** Exact retained expansion, used only as a new arithmetic proposal. *)

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
end

include S

module Fast : S
(** Cheaper enclosures. Wider intervals require refinement, never a weaker
    acceptance threshold. No shared mutable precision state. *)
