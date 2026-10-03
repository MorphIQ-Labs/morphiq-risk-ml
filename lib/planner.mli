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
