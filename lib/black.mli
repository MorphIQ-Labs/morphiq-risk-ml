(** The lognormal (Black) family on one kernel.

    BSM, Black-76 and displaced Black are applications of {!Make} to a {!CARRY}.
    A carry only maps the model's inputs to Black coordinates. The built-in
    models have distinct abstract [admitted] types, so a contract admitted by
    one cannot be used by another. Reusing the same carry module with this
    applicative functor can share its admitted type.

    Fast Greek results are checked per field for finiteness in their output
    units. Unresolved arithmetic returns [Greeks.Numerical_failure]; a finite
    result retains the documented checked-input accuracy scope. *)

module Coordinates : sig
  type live = private {
    asset : float;  (** [S e^(-qT)], scaled by [2^-exponent]. *)
    cash : float;  (** [K e^(-rT)], scaled by [2^-exponent]. *)
    x : float;  (** [ln(asset / cash)], high part. *)
    x_low : float;  (** Its low part: [x + x_low] carries about 106 bits. *)
    x_terms : float;
        (** [|ln(S/K)| + |(r - q)T|], the size of [x]'s parts before they
            cancel. *)
    exponent : int;  (** Prices are computed at scale [2^-exponent]. *)
    time : float;
    root_time : float;
    root_time_low : float;
    spot : float;  (** [S], scaled by [2^-exponent]. *)
    spot_low : float;
        (** [S]'s low part where [S] is an exact sum ([F + d]). *)
    strike : float;  (** [K], scaled by [2^-exponent]. *)
    strike_low : float;
    original_spot : float;
    original_spot_low : float;
    original_strike : float;
    original_strike_low : float;
        (** Exact unscaled input words retained for runtime decisions. *)
    rate : float;
    yield : float;
    tied : bool;  (** The yield is the rate (a forward model): rho moves both. *)
  }

  type t = private
    | Expiry of { spot : float; strike : float; rate : float; yield : float }
    | Live of live

  val exp_neg_product : float -> float -> float
  (** [e^(-(a b))] with the product split exactly. *)
end

module type CARRY = sig
  type inputs

  val coordinates : inputs -> (Coordinates.t, Refusal.t) result
end

module type MODEL = sig
  type inputs

  type admitted
  (** Inputs that passed this model's domain check. Only [admit] makes one. *)

  val admit : inputs -> (admitted, Refusal.t) result

  val price : admitted -> Side.t -> Vol.lognormal Vol.t -> float
  (** Fast approximate price. Severe carry cancellation uses a bounded
      original-input refinement and returns NaN if no rounding cell resolves.
      Admission does not promise numerical availability. Use {!Production} when
      a value must carry an explicit error certificate. *)

  val implied :
    admitted -> Side.t -> float -> (Vol.lognormal Iv.t, Refusal.t) result
  (** A correctly rounded positive inverse, a mathematical classification, or an
      explicit computational failure; see {!Iv.t}. A quote that is not a finite,
      nonnegative number is refused. *)

  val greeks :
    admitted -> Side.t -> Vol.lognormal Vol.t -> Vol.lognormal Greeks.t
  (** Severe carry cancellation or a computed zero coordinate unsupported by
      original-input ATM identity yields [Greeks.Numerical_failure] in every
      field. This is a numerical capability limit, not a payoff kink. *)

  val coordinates : admitted -> Coordinates.t
end

module Make (C : CARRY) : MODEL with type inputs = C.inputs

module Bsm_carry : sig
  type inputs = {
    spot : float;
    strike : float;
    time_to_expiry : float;
    rate : float;
    dividend_yield : float;
  }

  include CARRY with type inputs := inputs
end

module Black76_carry : sig
  type inputs = {
    forward : float;
    strike : float;
    time_to_expiry : float;
    rate : float;
  }

  include CARRY with type inputs := inputs
end

module Displaced_carry : sig
  type inputs = {
    forward : float;
    strike : float;
    displacement : float;
    time_to_expiry : float;
    rate : float;
  }

  include CARRY with type inputs := inputs
end

module Bsm : MODEL with type inputs = Bsm_carry.inputs
module Black76 : MODEL with type inputs = Black76_carry.inputs

module Displaced : MODEL with type inputs = Displaced_carry.inputs
(** Black-76 on the real numbers [forward + displacement] and
    [strike + displacement]. The sums are exact: never rounded, and carried as
    compensated words, including the runtime IV enclosure. Where they are
    representable, price, implied volatility and Greeks equal Black-76's on the
    sums bit for bit (docs/model-contracts.md). *)
