(** The lognormal (Black) family on one kernel.

    BSM, Black-76 and displaced Black are applications of {!Make} to a {!CARRY}.
    A carry only maps the model's inputs to Black coordinates. Each application
    has its own abstract [admitted] type, so a contract admitted by one model
    cannot be priced, inverted or differentiated by another. *)

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

  val implied :
    admitted -> Side.t -> float -> (Vol.lognormal Iv.t, Refusal.t) result
  (** The volatility whose price is the quote, or why there is none. A quote
      that is not a finite, nonnegative number is refused. *)

  val greeks :
    admitted -> Side.t -> Vol.lognormal Vol.t -> Vol.lognormal Greeks.t

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
    double-doubles throughout. Where they are representable, price, implied
    volatility and Greeks equal Black-76's on the sums bit for bit
    (docs/model-contracts.md). *)
