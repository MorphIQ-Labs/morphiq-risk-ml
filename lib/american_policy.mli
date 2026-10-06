type phase = Select | Eliminate | Substitute | Copy

type t
(** Internal operation-preserving blocks over exclusively owned solver arrays.
    Borrowed arrays must remain disjoint and must not be mutated concurrently.
    Calls do not allocate, release the runtime lock or retain pointers. *)

val create :
  lo:float array ->
  diag:float array ->
  hi:float array ->
  rhs:float array ->
  values:float array ->
  payoff:float array ->
  pivots:float array ->
  solution_rhs:float array ->
  candidate:float array ->
  mask:bool array ->
  oldmask:bool array ->
  t

val reset : t -> obstacle:bool -> unit

val run : t -> phase -> first:int -> last:int -> int
(** Inclusive block of at most 256 interior rows. Substitute runs descending;
    other phases ascend. Eliminate starts at row two or later. Status 0
    succeeds; 1 is a nonfinite policy decision; 2/3/4 are nonpositive previous
    pivot, nonfinite new pivot and nonfinite RHS; 5/6 are nonpositive
    substitution pivot and nonfinite solution. First failing row is included in
    [visited]. Malformed shapes/ranges or writable aliasing raise
    [Invalid_argument]. *)

val changed : t -> bool
val fingerprint : t -> int
val visited : t -> int
