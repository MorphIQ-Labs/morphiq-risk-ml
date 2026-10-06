(** Immutable, bounded European scenario plans. Compilation establishes
    structure and resource policy, not numerical admission of future shocked
    inputs. *)
type market =
  | Spot_market of { spot : float; volatility : Vol.lognormal Vol.t }
  | Forward_market of { forward : float; volatility : Vol.lognormal Vol.t }
  | Normal_market of { forward : float; volatility : Vol.normal Vol.t }

type factor = { name : string; market : market }

type model =
  | Bsm of { dividend_yield : float }
  | Black76
  | Displaced of float
  | Bachelier

type position = {
  id : string;
  factor : string;
  rate_factor : string;
  currency : string;
  quantity : float;
  model : model;
  strike : float;
  expiry_day : int;
  rate : float;
  side : Side.t;
}

type 'c output =
  | Output : ('c, 'a) Production.quantity * 'a -> 'c output
      (** Each output carries its caller-selected absolute scalar error limit.
      *)

type day_count = Actual_365_fixed | Actual_360
type output_mode = Stream | Aggregate_only

type limits = {
  max_instruments : int;
  max_scenarios : int;
  max_calculations : int;
  tile_rows : int;
  max_workers : int;
  max_buffered_results : int;
  max_groups : int;
}

type t

type explanation = {
  snapshot_id : string;
  kernels : string list;
  limits : limits;
  output_mode : output_mode;
  dependency_reuse : string;
  instruments : int;
  scenarios : int;
  calculations : int;
  tiles : int;
  raw_value_error_bytes : int;
  buffered_results : int;
  groups : int;
  plan_id : string;
  convention : string;
}

val compile :
  snapshot_id:string ->
  base_day:int ->
  day_count:day_count ->
  portfolio:position array ->
  market:factor array ->
  scenarios:Scenario.t ->
  lognormal_outputs:Vol.lognormal output list ->
  normal_outputs:Vol.normal output list ->
  output_mode:output_mode ->
  limits:limits ->
  (t, string) result
(** Copies caller arrays. Civil days are integral ordinals in [-1e9,1e9].
    Forward valuation offsets and frozen inputs are mandatory. All shocks start
    from that snapshot. Dates at expiry serve certified prices; smooth Greeks
    retain Production's explicit expiry refusal. Beyond expiry is unsupported.
    Duplicate position IDs, bindings and output quantities fail compilation. No
    full-cube materialization, economic P&L, quote scenarios or resume API. *)

val explain : t -> explanation

val manifest : t -> string
(** Versioned canonical plan identity, exact input bits, OCaml version and
    runtime word size. Execution callers must retain executable/toolchain hashes
    separately: a plan identity is not an executable identity. *)

type tile = private {
  id : int;
  scenario : int;
  first : int;
  length : int;
  plan_id : string;
}

val tile : t -> int -> tile
(** Lazy scenario-major tiles; instrument order is the portfolio order. *)

type coordinate = Lognormal | Normal
type error = Post_expiry | Scalar of Production.error

type outcome =
  | Outcome :
      ('c, 'a) Production.quantity * ('a Production.certified, error) result
      -> outcome

type row = {
  scenario_id : int;
  instrument_index : int;
  instrument_id : string;
  factor_id : string;
  currency : string;
  coordinate : coordinate;
  outcomes : outcome list;
}

val evaluate_tile : t -> tile -> (row array, string) result
(** Rejects a tile from another plan unless its identity and full logical extent
    match. No callbacks run inside evaluation; all worker scratch is local. *)

type bucket = {
  currency : string;
  factor : string;
  rate_factor : string;
  model : model;
  coordinate : coordinate;
  quantity_name : string;
}

type enclosed_total = private { value : float; absolute_error : float }

type summary = {
  scenario_id : int;
  bucket : bucket;
  successful : int;
  failed : int;
  successful_subset : enclosed_total option;
  complete : bool;
}
(** Ordered original-position reduction. [successful_subset] is never a complete
    total unless [complete]. None means aggregate arithmetic was unresolved;
    per-item success does not imply representability of the weighted total. *)

type stop =
  | Complete
  | Cancelled
  | Sink_failure of string
  | Worker_failure of string

type completion = {
  stop : stop;
  rows_committed : int;
  calculations_committed : int;
}

type event = Row of row | Summary of summary | Finished of completion
type cancellation

val cancellation : unit -> cancellation
val cancel : cancellation -> unit

val execute :
  t ->
  workers:int ->
  cancellation:cancellation ->
  sink:(event -> (unit, string) result) ->
  completion
(** Bounded fork/join waves. Only the coordinating domain invokes the sink,
    strictly in logical order. Aggregate-only mode emits rows containing errors
    as well as every summary. Sink rejection/exception stops output; no Finished
    marker can be promised for a broken sink. Cancellation emits Finished but
    never fabricates summaries of unvisited items. Never resumes/retries output.
    A fresh invocation is a new run and requires a fresh output destination. *)

module Fast : sig
  (** Bounded, price-only scenario streaming through the existing fast scalar
      kernels. Results are approximate prices without runtime certificates.
      Reuses the outer planner's model, market, date and scenario conventions.
  *)

  type limits = {
    max_instruments : int;
    max_scenarios : int;
    max_calculations : int;
    tile_rows : int;
    max_workers : int;
    max_buffered_results : int;
  }

  type t

  type explanation = {
    snapshot_id : string;
    kernels : string list;
    limits : limits;
    instruments : int;
    scenarios : int;
    calculations : int;
    tiles : int;
    raw_value_bytes : int;
    buffered_results : int;
    plan_id : string;
    convention : string;
  }

  val compile :
    snapshot_id:string ->
    base_day:int ->
    day_count:day_count ->
    portfolio:position array ->
    market:factor array ->
    scenarios:Scenario.t ->
    limits:limits ->
    (t, string) result
  (** Freezes caller arrays and validates structural/resource contracts. Every
      position/scenario pair requests one unweighted price, including
      zero-weight positions. Numerical/volatility admission occurs after each
      scenario's shocks. No accuracy limit, aggregate mode or synthetic
      certificate. *)

  val explain : t -> explanation

  val manifest : t -> string
  (** Records a distinct fast assurance convention and identity; certified
      planner identities and manifests are unchanged. Eight raw value bytes per
      calculation are a lower bound, excluding result/identity/heap overhead. *)

  type tile = private {
    id : int;
    scenario : int;
    first : int;
    length : int;
    plan_id : string;
  }

  val tile : t -> int -> tile

  type error = Post_expiry | Scalar of Batch.Fast.error

  type row = {
    scenario_id : int;
    instrument_index : int;
    instrument_id : string;
    factor_id : string;
    currency : string;
    coordinate : coordinate;
    quantity : float;
    price : (float, error) result;
  }
  (** [price] is per unit; [quantity] is the original position multiplier as
      metadata. It is not silently applied. No weighted totals or error bounds
      are produced. Failures retain their original row identity. *)

  val evaluate_tile : t -> tile -> (row array, string) result
  (** Rejects a foreign identity/extent; uses worker-local scratch. *)

  type event = Row of row | Finished of completion

  val execute :
    t ->
    workers:int ->
    cancellation:cancellation ->
    sink:(event -> (unit, string) result) ->
    completion
  (** Streams every row in scenario-major, original-position order. Shares the
      certified executor's bounded wave, join, cancellation and sink-failure
      semantics. All callbacks run on the coordinating domain. Reusing a plan
      requires a fresh output destination; no durable resume/retry is implied.
  *)
end

module American : sig
  module B = Batch.American
  (** Typed estimated/certified early-exercise scenario streaming. No aggregate
      total or implicit promotion of estimates to certificates. *)

  type 'a curve = { initial : 'a; changes : (int * 'a) array }

  type _ model =
    | Constant : {
        rate : float;
        dividend_yield : float;
        volatility : Vol.lognormal Vol.t;
      }
        -> B.constant model
    | Piecewise : {
        rate : float curve;
        dividend_yield : float curve;
        volatility : Vol.lognormal Vol.t curve;
      }
        -> B.piecewise model

  type instant = { day : int; side : Early_exercise.Bsm.event_side }

  type exercise =
    | American of {
        opening : instant;
        expiry_side : Early_exercise.Bsm.event_side;
      }
    | Bermudan of instant array

  type dividend = { day : int; amount : float }

  type 'k specification = {
    id : string;
    factor : string;
    currency : string;
    quantity : float;
    strike : float;
    expiry_day : int;
    side : Side.t;
    model : 'k model;
    exercise : exercise;
    cash : dividend array option;
    outputs : 'k B.output list;
  }

  type position = Position : 'k specification -> position
  type factor = { name : string; spot : float }
  type cash_at_valuation = Before_payment | After_payment

  type limits = {
    max_instruments : int;
    max_market_factors : int;
    max_scenarios : int;
    max_calculations : int;
    tile_rows : int;
    max_workers : int;
    max_buffered_results : int;
    max_solver_workspace_bytes : int;
    max_schedule_events : int;
  }

  type t

  type explanation = {
    snapshot_id : string;
    plan_id : string;
    convention : string;
    limits : limits;
    instruments : int;
    scenarios : int;
    calculations : int;
    tiles : int;
    buffered_results : int;
    dependency_reuse : string;
  }

  val compile :
    snapshot_id:string ->
    base_day:int ->
    day_count:day_count ->
    cash_at_valuation:cash_at_valuation ->
    portfolio:position array ->
    market:factor array ->
    scenarios:Scenario.t ->
    limits:limits ->
    (t, string) result
  (** Supported on the qualified 64-bit runtimes. Freeze all arrays; validate
      the complete original schedule and unshocked base model before scenario
      filtering. Future shocked admission is per-row. Dates/knots lie in the
      declared base-to-expiry interval (American opening may precede base).
      Volatility shocks map each original coefficient level; spot shocks act on
      frozen factor spot. Rates/yields/quotes stay fixed. Each remaining year
      fraction is a single division of an integer day difference. No dividend
      adjustment to the supplied valuation-side spot. Output slots count
      operations, including one slot per Greek bundle. No full scenario cube,
      aggregate mode, settlement or economic P&L. *)

  val explain : t -> explanation
  val manifest : t -> string

  type tile = private {
    id : int;
    scenario : int;
    first : int;
    length : int;
    plan_id : string;
  }

  val tile : t -> int -> tile

  type error =
    | Post_expiry
    | Admission of Early_exercise.Bsm.input_error
    | Volatility of Refusal.t
    | Scalar of B.error

  type outcome =
    | Outcome : ('k, 'a) B.operation * ('a, error) result -> outcome

  type row = {
    scenario_id : int;
    instrument_index : int;
    instrument_id : string;
    factor_id : string;
    currency : string;
    quantity : float;
    outcomes : outcome list;
  }

  type event = Row of row | Finished of completion

  val evaluate_tile : t -> tile -> (row array, string) result
  (** Full unweighted ordered results for one owned tile; fresh arrays. *)

  val execute :
    t ->
    workers:int ->
    cancellation:cancellation ->
    sink:(event -> (unit, string) result) ->
    completion
  (** Ordered bounded waves using worker-owned scalar scratch. Cancellation
      reaches scalar kernels and date preparation; an interrupted row is not
      committed. Workers join before return. The coordinator alone invokes the
      sink. Counters describe only sink-accepted rows/operation slots; already
      computed uncommitted work is discarded. Sink failure has no guaranteed
      Finished marker. Each execution requires a fresh output destination. *)
end
