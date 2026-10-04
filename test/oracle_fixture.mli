(** Read and validate one immutable snapshot before scoring any row. *)
val validate :
  columns:int list ->
  expected:(int * string) option ->
  string ->
  (string list, string) result
(** Expected row count and BLAKE2b-256 of all uncompressed bytes. Repeated input
    values in the original corpus are legitimate; changed row multiplicity,
    order, content and truncation fail the fingerprint. *)

val lines :
  ?external_reference:bool ->
  columns:int list ->
  names:string list ->
  string ->
  string list
(** Default: bytes must match one of the named verified committed fixtures.
    Explicit external comparisons have no completeness/provenance claim and are
    labelled accordingly. Input failures exit 3, never a numerical kill. *)
