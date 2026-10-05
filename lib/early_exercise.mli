(** Estimated American prices. These results are not [Production] certificates.
    See [docs/american-pricing.md] for numerical capability and limitations. *)
module Bsm : sig
  type inputs = {
    spot : float;
    strike : float;
    rate : float;
    dividend_yield : float;
    time_to_expiry : float;
    opens_at : float;
    volatility : Vol.lognormal Vol.t;
  }

  type admitted
  type input_error = Invalid_input of string

  val admit : inputs -> (admitted, input_error) result
  (** Constant coefficients, continuous yield, no cash dividends. Exercise is
      allowed throughout [opens_at,time_to_expiry], including both endpoints.
      Every original field is validated before boundary dispatch. *)

  val inputs : admitted -> inputs

  type limits = {
    max_nodes : int;
    max_steps : int;
    max_policy_solves : int;
    max_row_visits : int;
    max_workspace_bytes : int;
    policy_iterations : int;
  }

  type configuration

  val configure :
    tolerance:float ->
    space_cells:int ->
    time_steps:int ->
    domain_expansions:int ->
    limits:limits ->
    (configuration, string) result
  (** Three space/time levels [n,2n,4n], and at least two domain doublings
      starting at [4*max(S,K)]. Limits cover the whole request. The positive
      tolerance is a refinement target, never a promised price error. *)

  type refinement = {
    space_changes : float * float;
    time_changes : float * float;
    domain_changes : float * float;
    boundary_half_spread : float;
    observed_sum : float;
  }

  type failure =
    | Resource_limit of string
    | Cancelled
    | Arithmetic_unresolved of string
    | Unrepresentable
    | Nonconvergence of { step : int; row : int; residual : float }
    | Accuracy_not_demonstrated of refinement

  type work = {
    steps : int;
    policy_solves : int;
    row_visits : int;
    largest_grid : int;
    final_nodes : int;
    final_upper_stock : float;
    finest_steps_per_slab : int;
    domain_expansions : int;
    switched_rows : int;
  }

  type region_kind = Estimated_exercise | Estimated_continuation | Unresolved
  type region = { lower_stock : float; upper_stock : float; kind : region_kind }
  type 'a diagnostic = Not_requested | Unavailable of string | Available of 'a

  type premium = {
    value : float;
    european_value : float;
    european_absolute_error : float;
    subtraction_indicator : float;
  }
  (** The European comparison is enclosed separately. The American component
      remains estimated, so the premium has no full-price error bound. *)

  type assurance = Estimated_only

  type estimated_price = private {
    value : float;
    assurance : assurance;
    method_name : string;
    requested_tolerance : float;
    refinement : refinement option;
    maximum_residual : float;
    maximum_roundoff_indicator : float;
    boundary_arithmetic_indicator : float;
    work : work;
    exercise_regions : region list diagnostic;
    early_exercise_premium : premium diagnostic;
  }

  val price :
    ?cancel:(unit -> bool) ->
    ?exercise_regions:bool ->
    ?premium:bool ->
    configuration ->
    admitted ->
    Side.t ->
    (estimated_price, failure) result
  (** Single-threaded, call-owned scratch. Cancellation is checked before
      allocation, every step/policy solve, at most every 256 numerical rows, and
      before success. Exceptions from the caller's callback propagate. Failed
      requests never return a usable partial price. Optional diagnostics report
      their own availability. Finite-input admission does not imply that the
      requested resolution is achievable. *)
end
