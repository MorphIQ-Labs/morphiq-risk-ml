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

module Fast : sig
  (** Fast approximate prices, without runtime error certificates. Compilation
      reuses scalar admission; it does not establish numerical availability. *)

  type request = Price : ('i, 'c) model * 'i * Side.t * 'c Vol.t -> request
  type error = Invalid_input of Refusal.t | Numerical_failure

  type outcome = (float, error) result
  (** Success is a finite, nonnegative approximate price in the model's price
      units. NaN, infinity and negative scalar outputs are numerical failures.
      No value is clamped; finite successful words, including zero signs, are
      preserved. This is not a [Production.certified] value. *)

  val evaluate : request -> outcome

  val run : request array -> outcome array
  (** One-shot admission and pricing, with one ordered result per input. Empty
      input yields empty output. Callers must not mutate input arrays during the
      call; returned arrays are fresh. *)

  type t
  (** An immutable frozen batch of admitted inputs or per-item admission errors.
      Model inputs, sides and volatilities are fixed. Changed inputs require a
      new compilation. No cross-item value cache or numerical result is stored.
  *)

  val compile : request array -> t
  (** Admits each item once and snapshots the supplied array. Admission errors
      remain at their original indices. Do not mutate the array during this
      call; mutation afterwards cannot affect the compiled batch. O(n) retained
      storage; callers control n. No scenario cube or worker pool is created. *)

  val length : t -> int

  val execute : t -> outcome array
  (** Prices every admitted item without repeating admission; allocates a fresh
      ordered result array. Safe to reuse/concurrently execute one immutable
      batch. Mutating returned arrays cannot affect future executions. Expected
      numerical failures are per-item; programming/runtime exceptions propagate.
  *)
end
