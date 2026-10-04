(** Sequential, scalar-equivalent requests. Input records and typed operations
    are immutable; [run] allocates a fresh result array, never an output alias.
    Empty arrays return empty arrays. Every entry has exactly one result. No
    admission bypass, tolerance default or numerical transformation. *)
type (_, _) model =
  | Bsm : (Black.Bsm.inputs, Vol.lognormal) model
  | Black76 : (Black.Black76.inputs, Vol.lognormal) model
  | Displaced : (Black.Displaced.inputs, Vol.lognormal) model
  | Bachelier : (Bachelier.inputs, Vol.normal) model

type (_, _) operation =
  | Evaluate :
      'c Vol.t * ('c, 'a) Production.quantity * 'a
      -> ('c, 'a Production.certified) operation
  | Implied : float -> ('c, 'c Iv.t) operation

type 'a request =
  | Request : ('i, 'c) model * 'i * Side.t * ('c, 'a) operation -> 'a request

val evaluate : 'a request -> ('a, Production.error) result

val run : 'a request array -> ('a, Production.error) result array
(** Callers must not concurrently mutate the supplied array during [run]. No
    references to it are retained after return. Heterogeneous operations can be
    packaged by the caller without erasing their typed results. *)

val evaluate_many :
  ('i, 'c) model ->
  'i ->
  Side.t ->
  'c Vol.t ->
  'c Production.request list ->
  'c Production.outcome list
(** Admit one fixed model/input group and evaluate the ordered quantities with
    per-output limits. Shares preparation only within this call. Admission
    errors appear for every requested output; an empty list returns an empty
    list. *)
