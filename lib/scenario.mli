(** Versioned deterministic scenarios. Shock arithmetic is part of the scenario
    convention, not the exact-real pricing model: each generated binary64
    coordinate becomes an exact input to scalar admission. No repeated addition.
    All constructors freeze caller-owned arrays; no writable aliases escape. *)
type field = Spot | Forward | Lognormal_volatility | Normal_volatility

type adjustment = Replace of float | Add of float | Scale of float
type shock = { factor : string; field : field; adjustment : adjustment }
type point = { offset_days : int; shocks : shock list }
type range

val levels : float array -> (range, string) result

val linear : first:float -> step:float -> count:int -> (range, string) result
(** Value i is [Float.fma (float i) step first], with value 0 exactly [first].
    Count is explicit, including zero; indices must fit exactly in binary64. The
    final generated value must be finite. No implied terminal endpoint. *)

val range_count : range -> int
val range_value : range -> int -> float

type mode = Absolute | Additive | Relative

type axis =
  | Market of { factor : string; field : field; mode : mode; range : range }
  | Time of int array

type t

val paired : point array -> (t, string) result

val cartesian : axis list -> (t, string) result
(** Last axis varies fastest. No axes means one unshocked scenario; an empty
    axis means no scenarios. Duplicate factor/field axes or time axes fail. Roll
    offsets must be in [0, 1000000000] civil days. *)

val count : t -> int
val point : t -> int -> point
val bindings : t -> (string * field) list

val encoding : t -> string
(** Canonical length-prefixed, exact-bit representation, version 1. *)

val apply : adjustment -> float -> float
