(** MorphIQ Risk: option pricing, implied volatility and Greeks.

    The models are defined in docs/model-contracts.md, and every served quantity
    is measured against those definitions (docs/results-slice.md). The stability
    policy (docs/stability.md) covers everything here except {!Internal}.

    {!Production} provides enforced per-request numerical acceptance with
    explicit typed absolute limits and private certificates. The fast model
    functions below retain their documented checked-input assurance scope;
    mathematical admission alone is not a numerical output certificate.

    {1 Use}

    {[
      let a =
        Black.Bsm.admit
          {
            spot = 100.;
            strike = 95.;
            time_to_expiry = 0.5;
            rate = 0.03;
            dividend_yield = 0.01;
          }
      in
      match (a, Vol.lognormal 0.2) with
      | Ok a, Ok sigma -> Black.Bsm.price a Side.Call sigma
      | Error e, _ | _, Error e -> failwith (Refusal.to_string e)
    ]} *)

val version : string
(** The library's semantic version. *)

module Side = Side
module Refusal = Refusal
module Vol = Vol
module Units = Units
module Iv = Iv
module Greeks = Greeks
module Black = Black

module Bachelier : sig
  (** European options under the normal (Bachelier) model.

      Fast Greek results are checked per field for finiteness in their output
      units. Unresolved arithmetic returns [Greeks.Numerical_failure]; a finite
      result retains the documented checked-input accuracy scope. *)

  type inputs = Bachelier.inputs = {
    forward : float;
    strike : float;
    time_to_expiry : float;
    rate : float;
  }

  type admitted = Bachelier.admitted
  (** Inputs that passed the domain check. Only {!admit} constructs one. *)

  val admit : inputs -> (admitted, Refusal.t) result
  (** Forward and strike may take any finite sign. *)

  val price : admitted -> Side.t -> Vol.normal Vol.t -> float

  val implied :
    admitted -> Side.t -> float -> (Vol.normal Iv.t, Refusal.t) result
  (** A correctly rounded positive inverse, a mathematical classification, or an
      explicit computational failure; see {!Iv.t}. *)

  val greeks : admitted -> Side.t -> Vol.normal Vol.t -> Vol.normal Greeks.t
end

module Normal = Normal
module Batch = Batch
module Scenario = Scenario
module Planner = Planner
module Exchange = Exchange
module Early_exercise = Early_exercise

module Production : module type of Production
(** Numerical building blocks, exposed for testing and research. They are not
    covered by the stability policy and may change in any release. *)

module Internal : sig
  module Bachelier_fast : sig
    type t = private { q : float; low : float; s : float; discount : float }

    val may_prepare : Bachelier.inputs -> Side.t -> Vol.normal Vol.t -> bool
    val prepare : Bachelier.admitted -> Side.t -> Vol.normal Vol.t -> t option
    val price : t -> float
  end

  module Bachelier_native : sig
    type t

    val backend : int
    val default_enabled : bool
    val compile : Bachelier_fast.t array -> t
    val length : t -> int
    val execute : ?scalar:bool -> t -> float array
  end

  module American_residual = American_residual
  module American_policy = American_policy
  module Elementary = Elementary
  module Cody = Cody
  module Split = Split
  module Dd = Dd
  module Normal_dd = Normal_dd
  module Normalised_black = Normalised_black
  module Lbr = Lbr
  module Iv_iteration = Iv_iteration
  module Enclosure = Enclosure
  module Model_enclosure = Model_enclosure
  module Certified_iv = Certified_iv
  module Adaptive_iv = Adaptive_iv
end
