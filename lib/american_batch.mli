type constant
(** Immutable compiled requests for the qualified scalar early-exercise APIs. No
    value-surface cache, worker pool or implicit aggregate is created. *)

type piecewise

type _ model =
  | Constant : Early_exercise.Bsm.admitted -> constant model
  | Piecewise : Early_exercise.Bsm.Piecewise.admitted -> piecewise model

type (_, _) operation =
  | Price : {
      pricing : Early_exercise.Bsm.configuration;
      premium : bool;
      exercise_regions : bool;
    }
      -> ('k, Early_exercise.Bsm.estimated_price) operation
  | Greeks :
      Early_exercise.Bsm.configuration * Early_exercise.Bsm.greek_configuration
      -> ('k, Early_exercise.Bsm.estimated_greeks) operation
  | Implied :
      Early_exercise.Bsm.Implied_volatility.settings
      * Early_exercise.Bsm.Implied_volatility.quote
      -> ( constant,
           Early_exercise.Bsm.Implied_volatility.estimated_interval )
         operation
  | Certified_price :
      Early_exercise.Bsm.Certified.absolute_error_limit
      -> (constant, Early_exercise.Bsm.Certified.price) operation

type 'k output = Output : ('k, 'a) operation -> 'k output

type request =
  | Request : {
      id : string;
      model : 'k model;
      side : Side.t;
      outputs : 'k output list;
    }
      -> request

type error =
  | Pricing of Early_exercise.Bsm.failure
  | Certification of Early_exercise.Bsm.Certified.error
  | Inverse of Early_exercise.Bsm.Implied_volatility.error

type outcome = Outcome : ('k, 'a) operation * ('a, error) result -> outcome
type row = { id : string; outcomes : outcome list }

type limits = {
  max_requests : int;
  max_outputs : int;
  max_solver_workspace_bytes : int;
}
(** Outputs count requested operations; a Greek bundle is one slot containing
    its explicitly requested quantities and bounded scalar diagnostics. The
    workspace limit bounds each configured PDE allowance, not allocation/RSS or
    certificate runtime storage. *)

type t

val compile : limits:limits -> request array -> (t, string) result
(** Snapshot the array; require distinct nonempty IDs and bounded operation
    counts/workspace allowances. Admitted models already own frozen schedules.
    No numerical execution or certificate acceptance occurs at compilation. *)

val length : t -> int
val manifest : t -> string
val evaluate : ?cancel:(unit -> bool) -> request -> row

val execute : ?cancel:(unit -> bool) -> t -> row array
(** Fresh ordered arrays on each invocation. Independent concurrent executions
    share only immutable admission/configuration. Scalar callback exceptions
    propagate. Cancellation remains an explicit scalar outcome for each output;
    this direct batch API has no streaming-prefix completion marker. *)

val output_encoding : 'k output -> string
(** Canonical exact-word operation/configuration identity, version 1. *)

val output_workspace : 'k output -> int
(** Configured scalar workspace allowance; zero for certificates, whose own
    bounded European arithmetic has no caller-selected PDE allowance. *)
