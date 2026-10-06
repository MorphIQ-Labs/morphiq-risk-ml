(** Estimated American and Bermudan prices and Greeks. These results are not
    [Production] certificates. See [docs/american-pricing.md] for numerical
    capability and limitations. *)
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

  type event_side = Regular | Before_cash | After_cash
  type dividend = { time : float; amount : float }

  type cash_specification = {
    valuation_side : event_side;
    opening_side : event_side;
    expiry_side : event_side;
    dividends : dividend array;
  }

  type exercise_instant = { time : float; side : event_side }
  type admitted
  type input_error = Invalid_input of string

  val admit : inputs -> (admitted, input_error) result
  (** Constant coefficients, continuous yield, no cash dividends. Exercise is
      allowed throughout [opens_at,time_to_expiry], including both endpoints.
      Every original field is validated before boundary dispatch. *)

  val admit_cash :
    inputs -> cash_specification -> (admitted, input_error) result
  (** Freeze an ordered schedule of finite nonnegative amounts in [0,T]. Cash at
      one time forms one joint exact sum, with jump [max(S-D,0)]. Zero amounts
      retain event identity. Event sides are mandatory exactly at cash dates;
      valuation precedes opening, which precedes expiry in instant order. An
      [After_cash] valuation does not subtract the valuation-date payment again.
      The input array is copied; malformed schedules fail before any pricing. *)

  val admit_bermudan :
    ?cash:cash_specification ->
    inputs ->
    exercise_instant array ->
    (admitted, input_error) result
  (** Freeze nonempty strictly ordered exercise instants. First/last match
      [opens_at]/expiry and their cash sides. Regular is required off cash
      dates; Before/After on cash dates. Both sides at one date are distinct
      rights. Reject duplicates, unsorted dates and missing expiry. Arrays are
      copied. Numerical time refinement never adds exercise rights. *)

  val exercise_schedule : admitted -> exercise_instant array option
  (** A fresh copy for Bermudan admission, including terminal-only schedules;
      [None] identifies continuous American exercise. *)

  val cash_specification : admitted -> cash_specification option
  (** Returns a copy of the frozen schedule. *)

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
    event_changes : (float * float) option;
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
      remains estimated, so the premium has no full-price error bound. Cash
      requests currently report this optional comparison as [Unavailable]. *)

  type mapping = {
    event_applications : int;
    maximum_cell_width : float;
    arithmetic_indicator : float;
  }
  (** Work across all solves and interpolation diagnostics, not a bound on the
      event discretization error. Independent mapping refinement is recorded in
      [refinement.event_changes]. *)

  type assurance = Estimated_only

  type estimated_price = private {
    value : float;
    assurance : assurance;
    method_name : string;
    requested_tolerance : float;
    refinement : refinement option;
    mapping : mapping option;
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

  type greek = Delta | Gamma | Vega | Rho | Theta
  type greek_request

  val request_greek :
    ?bump:float -> tolerance:float -> greek -> (greek_request, string) result
  (** Positive finite absolute refinement target, in the Greek's units. Vega/rho
      require a positive initial parallel bump; other quantities reject bumps.
      Delta/gamma vary spot. Vega/rho are per unit annual lognormal
      volatility/continuous rate; rho holds yield fixed. Theta is per day,
      valuation time moving forward with absolute future events fixed. *)

  type greek_configuration

  val configure_greeks :
    greek_request list -> (greek_configuration, string) result
  (** One to five distinct quantities, in caller order. *)

  type greek_diagnostics = {
    derivative_refinement : refinement option;
    bump_changes : (float * float) option;
    stencil_change : float;
    arithmetic_indicator : float;
    amplified_price_indicator : float;
  }
  (** Empirical diagnostics, not continuum error bounds. Underlying price
      uncertainty remains visible separately from derivative refinement. *)

  type estimated_greek = private {
    value : float;
    assurance : assurance;
    requested_tolerance : float;
    method_name : string;
    diagnostics : greek_diagnostics;
  }

  type greek_outcome =
    | Greek_estimate of estimated_greek
    | Greek_unavailable of string
    | Greek_failure of failure
    | Greek_accuracy_not_demonstrated of greek_diagnostics

  type perturbation_price = private {
    quantity : greek;
    shift : float;
    price : estimated_price;
  }
  (** Coordinate and exact parallel displacement identify each accepted price.
  *)

  type estimated_greeks = private {
    price : estimated_price;
    greeks : (greek * greek_outcome) list;
    perturbation_prices : perturbation_price list;
  }

  val greeks :
    ?cancel:(unit -> bool) ->
    configuration ->
    greek_configuration ->
    admitted ->
    Side.t ->
    (estimated_greeks, failure) result
  (** Estimated-only outcomes, with the accepted base and perturbed prices. The
      request's work limits are partitioned across its maximum number of solves
      and derivative preparation; workspace includes call-owned Greek scratch.
      Cancellation/resource exhaustion fails the whole request. Unresolved
      exercise neighborhoods, non-smooth events and unqualified analytical
      stopping regimes explicitly decline individual quantities. Parallel bumps
      must preserve the exact original real shift at every level. No higher
      Greeks or certified results are produced. *)

  module Piecewise : sig
    (** Complete right-continuous partitions of [0,horizon]. The initial level
        starts at zero; changes are strictly increasing interior knots. Expiry
        uses the final left limit. No extrapolation, averaging, or sorting.
        Getters copy arrays and retain redundant original knots. *)
    module Rate : sig
      type t

      val create :
        horizon:float ->
        initial:float ->
        changes:(float * float) array ->
        (t, input_error) result

      val horizon : t -> float
      val initial : t -> float
      val changes : t -> (float * float) array
    end

    module Yield : sig
      type t

      val create :
        horizon:float ->
        initial:float ->
        changes:(float * float) array ->
        (t, input_error) result

      val horizon : t -> float
      val initial : t -> float
      val changes : t -> (float * float) array
    end

    module Volatility : sig
      type t

      val create :
        horizon:float ->
        initial:Vol.lognormal Vol.t ->
        changes:(float * Vol.lognormal Vol.t) array ->
        (t, input_error) result

      val horizon : t -> float
      val initial : t -> Vol.lognormal Vol.t
      val changes : t -> (float * Vol.lognormal Vol.t) array
    end

    type inputs = {
      spot : float;
      strike : float;
      rate : Rate.t;
      dividend_yield : Yield.t;
      time_to_expiry : float;
      opens_at : float;
      volatility : Volatility.t;
    }

    type admitted

    val admit : inputs -> (admitted, input_error) result

    val admit_cash :
      inputs -> cash_specification -> (admitted, input_error) result

    val admit_bermudan :
      ?cash:cash_specification ->
      inputs ->
      exercise_instant array ->
      (admitted, input_error) result
    (** Each curve's declared horizon must equal expiry exactly. Cash/exercise
        admission retains the constant API's event-side and ownership rules.
        Coefficient knots confer no additional finite exercise rights. *)

    val inputs : admitted -> inputs
    val cash_specification : admitted -> cash_specification option
    val exercise_schedule : admitted -> exercise_instant array option

    val price :
      ?cancel:(unit -> bool) ->
      ?exercise_regions:bool ->
      ?premium:bool ->
      configuration ->
      admitted ->
      Side.t ->
      (estimated_price, failure) result
    (** Estimated-only, bounded request-owned execution. Constant or redundantly
        split constant curves delegate to constant pricing. A parallel rate or
        yield perturbation shifts every annual continuous level; a segment
        perturbation changes one original level. Volatility perturbations use
        annual lognormal units. *)

    val greeks :
      ?cancel:(unit -> bool) ->
      configuration ->
      greek_configuration ->
      admitted ->
      Side.t ->
      (estimated_greeks, failure) result
    (** Same units, outcomes and whole-request limits as constant [greeks].
        Vega/rho shift every level of the corresponding curve; knots, cash
        amounts and exercise instants stay fixed. Bucketed risks are deferred.
    *)
  end
end
