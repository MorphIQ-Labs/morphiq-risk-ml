(* The lognormal (Black) family on one kernel. A model only says how its
   inputs map to Black coordinates (see CARRY); the functor supplies
   admission and pricing. *)

let invalid parameter value = Error (Refusal.Invalid_input { parameter; value })
let positive_finite v = Float.is_finite v && v > 0.0

module Coordinates = struct
  type live = {
    asset : float;  (** S e^(-qT): the discounted forward. *)
    cash : float;  (** K e^(-rT): the discounted strike. *)
    x : float;  (** ln(asset / cash), high part. *)
    x_low : float;  (** Its low part: x + x_low is ln(asset / cash) to ~106 bits. *)
    exponent : int;  (** Prices are computed on inputs scaled by 2^-exponent. *)
    time : float;
    root_time : float;
    root_time_low : float;  (** sqrt T = root_time + root_time_low to ~106 bits. *)
  }

  type t = Expiry of { spot : float; strike : float } | Live of live

  (* e^(-(a b)) with the product a b split exactly. *)
  let exp_neg_product a b =
    let p = a *. b in
    let lo = Float.fma a b (-.p) in
    if p >= 0.0 then Split.scaled_exp_neg 1.0 p lo else Float.exp (-.p) *. (1.0 -. lo)

  (* ln(S / K) in double-double, carrying the remainder of the quotient. *)
  let log_ratio s k =
    let q, r = Split.quotient s k in
    if Float.is_finite q && q >= Float.min_float then Dd.add (Dd.log_float q) (Dd.of_float (r /. q))
    else Dd.sub (Dd.log_float s) (Dd.log_float k)

  (* (r - q) T in double-double: both products are exact. *)
  let carry ~rate ~yield ~time = Dd.sub (Dd.two_prod rate time) (Dd.two_prod yield time)

  let validate_carry ~time ~rate ~yield ~yield_parameter =
    if not (Float.is_finite time && time >= 0.0) then invalid Refusal.Time_to_expiry time
    else if not (Float.is_finite rate) then invalid Refusal.Rate rate
    else if not (Float.is_finite yield) then invalid yield_parameter yield
    else Ok ()

  (* Prices are homogeneous of degree one in (S, K): both are scaled by the
     power of two that centres them on 1, exactly, and the price is scaled
     back once. The legs then neither underflow nor overflow before they
     cancel. *)
  let make ~spot ~strike ~time ~rate ~yield =
    if time = 0.0 then Expiry { spot; strike }
    else
      let exponent = (snd (Float.frexp spot) + snd (Float.frexp strike)) / 2 in
      let spot' = Float.ldexp spot (-exponent) and strike' = Float.ldexp strike (-exponent) in
      let x = Dd.add (log_ratio spot strike) (carry ~rate ~yield ~time) in
      Live
        {
          asset = spot' *. exp_neg_product yield time;
          cash = strike' *. exp_neg_product rate time;
          x = x.hi;
          x_low = x.lo;
          exponent;
          time;
          root_time = fst (Split.sqrt time);
          root_time_low = snd (Split.sqrt time);
        }
end

module type CARRY = sig
  type inputs

  val coordinates : inputs -> (Coordinates.t, Refusal.t) result
end

module type MODEL = sig
  type inputs
  type admitted

  val admit : inputs -> (admitted, Refusal.t) result
  val price : admitted -> Side.t -> Vol.lognormal Vol.t -> float
  val coordinates : admitted -> Coordinates.t
end

(* θ (asset - cash), the discounted forward intrinsic before flooring. Near the
   money it is cash (e^x - 1), so the two legs' roundings do not cancel. *)
let forward_intrinsic theta (c : Coordinates.live) =
  if Float.abs c.x < 1.0 then
    theta *. c.cash *. (Float.expm1 c.x +. (Float.exp c.x *. c.x_low))
  else theta *. (c.asset -. c.cash)

let live_price side (c : Coordinates.live) sigma =
  let theta = Side.sign side in
  let { Dd.hi = s; lo = sl } = Dd.mul_float { Dd.hi = c.root_time; lo = c.root_time_low } sigma in
  let intrinsic = forward_intrinsic theta c in
  let m () = Float.sqrt c.asset *. Float.sqrt c.cash in
  if sigma = 0.0 then Float.ldexp (Float.max intrinsic 0.0) c.exponent
  else if c.x = 0.0 && s < 0x1p-500 then
    (* Exactly at the money b = erf(s/sqrt 8) = s/sqrt(2 pi) (1 - s^2/24 ...);
       s itself may underflow while m s does not, so s is never formed. *)
    Split.product_ldexp [ m (); Normalised_black.inv_sqrt_2pi; sigma; c.root_time ] c.exponent
  else if s = 0.0 then Float.ldexp (Float.max intrinsic 0.0) c.exponent
  else
    (* The out-of-the-money part, at -|x|, carrying x's low part with it. *)
    let x, xl = if c.x > 0.0 then (-.c.x, -.c.x_low) else (c.x, c.x_low) in
    let m = m () in
    if theta *. c.x > 0.0 then Float.ldexp (intrinsic +. Normalised_black.scaled m x xl s sl) c.exponent
    else
      (* Applying the scale inside the kernel keeps a deep out-of-the-money
         value from underflowing before it is scaled back. *)
      Normalised_black.scaled ~k:c.exponent m x xl s sl

let price_coordinates coordinates side sigma =
  match coordinates with
  | Coordinates.Expiry { spot; strike } -> Float.max (Side.sign side *. (spot -. strike)) 0.0
  | Coordinates.Live c -> live_price side c (Vol.to_float sigma)

module Make (C : CARRY) : MODEL with type inputs = C.inputs = struct
  type inputs = C.inputs
  type admitted = Coordinates.t

  let admit = C.coordinates
  let coordinates a = a
  let price a side sigma = price_coordinates a side sigma
end

module Bsm_carry = struct
  type inputs = { spot : float; strike : float; time_to_expiry : float; rate : float; dividend_yield : float }

  let coordinates i =
    if not (positive_finite i.spot) then invalid Refusal.Spot i.spot
    else if not (positive_finite i.strike) then invalid Refusal.Strike i.strike
    else
      Result.map
        (fun () -> Coordinates.make ~spot:i.spot ~strike:i.strike ~time:i.time_to_expiry ~rate:i.rate ~yield:i.dividend_yield)
        (Coordinates.validate_carry ~time:i.time_to_expiry ~rate:i.rate ~yield:i.dividend_yield
           ~yield_parameter:Refusal.Dividend_yield)
end

module Bsm = Make (Bsm_carry)

module Black76_carry = struct
  type inputs = { forward : float; strike : float; time_to_expiry : float; rate : float }

  let coordinates i =
    if not (positive_finite i.forward) then invalid Refusal.Forward i.forward
    else if not (positive_finite i.strike) then invalid Refusal.Strike i.strike
    else
      Result.map
        (fun () -> Coordinates.make ~spot:i.forward ~strike:i.strike ~time:i.time_to_expiry ~rate:i.rate ~yield:i.rate)
        (Coordinates.validate_carry ~time:i.time_to_expiry ~rate:i.rate ~yield:i.rate ~yield_parameter:Refusal.Rate)
end

module Black76 = Make (Black76_carry)

module Displaced_carry = struct
  type inputs = { forward : float; strike : float; displacement : float; time_to_expiry : float; rate : float }

  let coordinates i =
    if not (Float.is_finite i.forward) then invalid Refusal.Forward i.forward
    else if not (Float.is_finite i.strike) then invalid Refusal.Strike i.strike
    else if not (Float.is_finite i.displacement) then invalid Refusal.Displacement i.displacement
    else
      match
        Coordinates.validate_carry ~time:i.time_to_expiry ~rate:i.rate ~yield:i.rate ~yield_parameter:Refusal.Rate
      with
      | Error _ as e -> e
      | Ok () when i.time_to_expiry = 0.0 -> Ok (Coordinates.Expiry { spot = i.forward; strike = i.strike })
      | Ok () ->
          let f = i.forward +. i.displacement and k = i.strike +. i.displacement in
          if not (positive_finite f) then invalid Refusal.Shifted_forward f
          else if not (positive_finite k) then invalid Refusal.Shifted_strike k
          else Ok (Coordinates.make ~spot:f ~strike:k ~time:i.time_to_expiry ~rate:i.rate ~yield:i.rate)
end

module Displaced = Make (Displaced_carry)
