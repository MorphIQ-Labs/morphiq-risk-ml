type t
(** Internal operation-preserving residual blocks. Arrays are borrowed from one
    solver owner and must not be mutated concurrently. No pointer escapes a
    call; the runtime lock remains held. This is not a public pricing API. *)

val create :
  lo:float array ->
  diag:float array ->
  hi:float array ->
  rhs:float array ->
  values:float array ->
  payoff:float array ->
  t

val reset : t -> obstacle:bool -> unit

val run : t -> first:int -> last:int -> int
(** Evaluate an inclusive block of at most 256 interior rows. Status 0 succeeds;
    1/2 identify the original nonfinite residual/screen failures, in row order.
    Invalid shapes/ranges raise [Invalid_argument] before array access. *)

val visited : t -> int
(** Number of rows actually evaluated in the last block, including failure. *)

val worst : t -> float
val worst_row : t -> int
val indicator : t -> float
