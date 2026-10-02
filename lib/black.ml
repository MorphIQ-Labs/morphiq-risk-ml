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
    x_low : float;
        (** Its low part: x + x_low is ln(asset / cash) to ~106 bits. *)
    x_terms : float;
        (** |ln(S/K)| + |(r - q)T|: the size of x's parts, before they cancel.
        *)
    exponent : int;  (** Prices are computed on inputs scaled by 2^-exponent. *)
    time : float;
    root_time : float;
    root_time_low : float;
        (** sqrt T = root_time + root_time_low to ~106 bits. *)
    spot : float;  (** S, scaled by 2^-exponent. *)
    spot_low : float;
        (** S's low part, for a spot that is an exact sum (S + d). *)
    strike : float;  (** K, scaled by 2^-exponent. *)
    strike_low : float;
    rate : float;
    yield : float;
    tied : bool;  (** The yield is the rate (a forward model): rho moves both. *)
  }

  type t =
    | Expiry of { spot : float; strike : float; rate : float; yield : float }
    | Live of live

  (* e^(-(a b)) with the product a b split exactly. *)
  let exp_neg_product a b =
    let p = a *. b in
    let lo = Float.fma a b (-.p) in
    if p >= 0.0 then Split.scaled_exp_neg 1.0 p lo
    else Elementary.exp (-.p) *. (1.0 -. lo)

  (* ln(S / K) in double-double. With q = fl(S/K), S/K = q (1 + ρ) where
     ρ = (S - q K)/(q K) and S - q K is exact (fma). Then
     ln(S/K) = ln q + ρ - ρ^2/2 + O(ρ^3), |ρ| <= 2^-53, with ρ itself in
     double-double: a rounded ρ costs ~1e-33 in x, which matters when the
     result cancels to ~1e-18 of its terms (a zero-variance price at the
     forward). *)
  let log_ratio s k =
    let q = s /. k in
    if Float.is_finite q && q >= Float.min_float then
      let rho =
        Dd.div
          (Dd.of_float (Float.fma (-.q) k s))
          (Dd.mul_float (Dd.of_float k) q)
      in
      Dd.add (Dd.log_float q) (Dd.sub rho (Dd.mul_float (Dd.mul rho rho) 0.5))
    else Dd.sub (Dd.log_float s) (Dd.log_float k)

  (* (r - q) T in double-double: both products are exact. *)
  let carry ~rate ~yield ~time =
    Dd.sub (Dd.two_prod rate time) (Dd.two_prod yield time)

  let validate_carry ~time ~rate ~yield ~yield_parameter =
    if not (Float.is_finite time && time >= 0.0) then
      invalid Refusal.Time_to_expiry time
    else if not (Float.is_finite rate) then invalid Refusal.Rate rate
    else if not (Float.is_finite yield) then invalid yield_parameter yield
    else Ok ()

  (* Prices are homogeneous of degree one in (S, K): both are scaled by the
     power of two that centres them on 1, exactly, and the price is scaled
     back once. The legs then neither underflow nor overflow before they
     cancel. *)
  let make ?(tied = false) ?(spot_low = 0.0) ?(strike_low = 0.0) ~spot ~strike
      ~time ~rate ~yield () =
    if time = 0.0 then Expiry { spot; strike; rate; yield }
    else
      (* Floor, not truncation: the exponent must shift by exactly j when S and
         K both scale by 2^j, so a price is exactly homogeneous. *)
      let exponent =
        (snd (Float.frexp spot) + snd (Float.frexp strike)) asr 1
      in
      (* ln((S + Sl)/(K + Kl)) = ln(S/K) + Sl/S - Kl/K to first order. *)
      let ln_ratio = log_ratio spot strike
      and carried = carry ~rate ~yield ~time in
      let x =
        Dd.add (Dd.add ln_ratio carried)
          (Dd.of_float ((spot_low /. spot) -. (strike_low /. strike)))
      in
      let x_terms = Float.abs ln_ratio.hi +. Float.abs carried.hi in
      (* For a tiny intrinsic, leave room for its product with the cash
         leg before restoring the currency exponent. The lift depends only
         on dimensionless x, preserving power-of-two homogeneity. With
         x_terms <= 1 the input ratio is bounded by e, so lifted coordinates
         remain below 2^514. *)
      let exponent =
        if x.hi <> 0.0 && Float.abs x.hi < 0x1p-500 && x_terms <= 1.0 then
          exponent - 512
        else exponent
      in
      let scale v = Float.ldexp v (-exponent) in
      let spot' = scale spot and strike' = scale strike in
      Live
        {
          asset =
            spot' *. exp_neg_product yield time *. (1.0 +. (spot_low /. spot));
          cash =
            strike' *. exp_neg_product rate time
            *. (1.0 +. (strike_low /. strike));
          x = x.hi;
          x_low = x.lo;
          x_terms;
          exponent;
          time;
          root_time = fst (Split.sqrt time);
          root_time_low = snd (Split.sqrt time);
          spot = spot';
          spot_low = scale spot_low;
          strike = strike';
          strike_low = scale strike_low;
          rate;
          yield;
          tied;
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

  val implied :
    admitted -> Side.t -> float -> (Vol.lognormal Iv.t, Refusal.t) result

  val greeks :
    admitted -> Side.t -> Vol.lognormal Vol.t -> Vol.lognormal Greeks.t

  val coordinates : admitted -> Coordinates.t
end

(* The legs and the discounted forward intrinsic in double-double (~106
   bits), at the coordinates' scale. They decide where a quote falls relative
   to the zero-volatility price and the maximum. *)
let precise_legs (c : Coordinates.live) =
  let leg hi lo rate =
    Dd.mul (Dd.exp (Dd.neg (Dd.two_prod rate c.time))) { Dd.hi; lo }
  in
  let asset = leg c.spot c.spot_low c.yield
  and cash = leg c.strike c.strike_low c.rate in
  let x = { Dd.hi = c.x; lo = c.x_low } in
  (* C (e^x - 1) is exact in relative terms when x itself is: its error is
     2^-104 C (|ln(S/K)| + |(r - q)T|). Once those terms are large and
     cancel (a forward placed at the strike through carry), A - C is better,
     with error 2^-104 A. *)
  let forward_intrinsic =
    if Float.abs c.x <= 0.35 && c.x_terms <= 1.0 then Dd.mul cash (Dd.expm1 x)
    else Dd.sub asset cash
  in
  (asset, cash, forward_intrinsic)

let live_price side (c : Coordinates.live) sigma =
  let theta = Side.sign side in
  let { Dd.hi = s; lo = sl } =
    Dd.mul_float { Dd.hi = c.root_time; lo = c.root_time_low } sigma
  in
  (* θ (asset - cash) to ~106 bits: the zero-variance price is its correctly
     rounded value, the same boundary the inverse classifies quotes against. *)
  let intrinsic () =
    let _, _, forward_intrinsic = precise_legs c in
    Dd.mul_float forward_intrinsic theta
  in
  let zero_variance () =
    if
      c.spot = c.strike && c.spot_low = c.strike_low
      && Float.max (Float.abs c.rate) (Float.abs c.yield) *. c.time < 0x1p-500
    then
      (* Here I = S (r-q) T (1 + O(max(|r|,|q|) T)). The omitted
         relative term is below 2^-499. Form the leading product from
         mantissas: (r-q)T itself need not be representable. *)
      let rate =
        Dd.mul_float (Dd.sub (Dd.of_float c.rate) (Dd.of_float c.yield)) theta
      in
      if rate.hi <= 0.0 then 0.0
      else
        let rt, re = Float.frexp c.time in
        let _, de = Float.frexp rate.hi in
        let _, se = Float.frexp c.spot in
        let spot = Dd.scale { Dd.hi = c.spot; lo = c.spot_low } (-se) in
        let product = Dd.mul_float (Dd.mul spot (Dd.scale rate (-de))) rt in
        Dd.to_float_scaled product (c.exponent + se + de + re)
    else
      let i = intrinsic () in
      if i.hi > 0.0 then Dd.to_float_scaled i c.exponent else 0.0
  in
  let m () = Float.sqrt c.asset *. Float.sqrt c.cash in
  if sigma = 0.0 then zero_variance ()
  else if c.x = 0.0 && s < 0x1p-500 then
    (* Exactly at the money b = erf(s/sqrt 8) = s/sqrt(2 pi) (1 - s^2/24 ...);
       s itself may underflow while m s does not, so s is never formed. *)
    Split.product_ldexp
      [ m (); Normalised_black.inv_sqrt_2pi; sigma; c.root_time ]
      c.exponent
  else if s = 0.0 then zero_variance ()
  else
    (* The out-of-the-money part, at -|x|, carrying x's low part with it. *)
    let x, xl = if c.x > 0.0 then (-.c.x, -.c.x_low) else (c.x, c.x_low) in
    let m = m () in
    if theta *. c.x > 0.0 then
      Dd.to_float_scaled
        (Dd.add (intrinsic ())
           (Dd.of_float (Normalised_black.scaled m x xl s sl)))
        c.exponent
    else
      (* Applying the scale inside the kernel keeps a deep out-of-the-money
         value from underflowing before it is scaled back. *)
      Normalised_black.scaled ~k:c.exponent m x xl s sl

let price_coordinates coordinates side sigma =
  match coordinates with
  | Coordinates.Expiry { spot; strike; _ } ->
      Float.max (Side.sign side *. (spot -. strike)) 0.0
  | Coordinates.Live c -> live_price side c (Vol.to_float sigma)

let root sigma =
  match Vol.lognormal sigma with
  | Ok v -> Iv.Root v
  | Error _ -> Iv.Above_maximum

(* Invert a live quote. The quote is compared exactly (to ~106 bits) with
   the zero-volatility price and the maximum. Its out-of-the-money part is
   normalised and inverted by Let's Be Rational, then given one Newton
   correction against the extended-precision kernel. *)
let live_implied side (c : Coordinates.live) price =
  let theta = Side.sign side in
  let p = Float.ldexp price (-c.exponent) in
  let asset, cash, forward_intrinsic = precise_legs c in
  let intrinsic =
    if theta > 0.0 then forward_intrinsic else Dd.neg forward_intrinsic
  in
  let maximum = if theta > 0.0 then asset else cash in
  if Dd.compare_float maximum p <= 0 then Iv.Above_maximum
  else if intrinsic.hi > 0.0 && Dd.compare_float intrinsic p > 0 then
    (* Below the exact zero-volatility price. A quote equal to that price's
       correctly rounded value is its binary64 rounding, so σ = 0 (#448). *)
    if p = intrinsic.hi then root 0.0 else Iv.Below_intrinsic
  else
    let otm =
      Dd.sub (Dd.of_float p)
        (if intrinsic.hi > 0.0 then intrinsic else Dd.of_float 0.0)
    in
    (* A positive quote can underflow to 0 when rescaled by 2^-exponent. It
       still has a positive root: the inversion then runs on ln β, taken from
       the unscaled quote. *)
    let underflowed = otm.hi = 0.0 && intrinsic.hi <= 0.0 && price > 0.0 in
    if otm.hi = 0.0 && not underflowed then root 0.0
    else
      let x, xl = if c.x > 0.0 then (-.c.x, -.c.x_low) else (c.x, c.x_low) in
      (* m = sqrt(A C) and β = otm/m from the double-double legs: three
         roundings in m would otherwise reach σ amplified by the inverse's
         conditioning β/(s b'), several ULP at high volatility. *)
      let m_dd = Dd.mul (Dd.sqrt asset) (Dd.sqrt cash) in
      let m = Dd.to_float m_dd in
      let beta =
        Float.max
          (Dd.to_float (Dd.div otm m_dd))
          (if underflowed then 0x1p-1074 else 0.0)
      in
      (* ln β from the unscaled quote where nothing is subtracted from it: β
         itself can be subnormal, and rescaling a subnormal quote by
         2^-exponent drops its bits. LBR's lowest branch works on ln β. *)
      let ln_beta =
        (if intrinsic.hi > 0.0 then Elementary.log (Dd.to_float otm)
         else Elementary.log price -. (float c.exponent *. Split.ln2_hi))
        -. Elementary.log m
      in
      (* β̄ = b_max - β from the exact distance to the maximum: near the
         maximum β itself rounds to b_max and loses it. *)
      let beta_bar =
        Dd.to_float (Dd.div (Dd.sub maximum (Dd.of_float p)) m_dd)
      in
      let b_max = Elementary.exp (0.5 *. x) in
      if beta <= 0.0 then Iv.Below_smallest_volatility
      else
        let beta = Float.min beta (Float.pred b_max) in
        let s = Lbr.solve ~beta_bar ~ln_beta beta x in
        let s =
          if not (Float.is_finite s && s > 0.0) then s
          else if beta > 0.5 *. b_max then
            (* Correct on the complement: β - b = b̄(s) - β̄. *)
            s
            +. (Normalised_black.complement x xl s 0.0 -. beta_bar)
               /. Normalised_black.vega x s
          else if beta < 0x1p-900 then
            (* β is near or in the subnormals, where it keeps few bits (and a
               subnormal quote loses more to rescaling). Newton on ln b, from
               the exact ln β: s += (ln β - ln b) b / b'. *)
            let ln_b, bx = Normalised_black.ln_b_and_scaled x xl s in
            s +. ((ln_beta -. ln_b) *. bx)
          else
            s
            +. (beta -. Normalised_black.scaled 1.0 x xl s 0.0)
               /. Normalised_black.vega x s
        in
        (* σ = s / sqrt T, with sqrt T's low part. *)
        let sigma =
          s /. c.root_time *. (1.0 -. (c.root_time_low /. c.root_time))
        in
        if Float.is_nan sigma || sigma = Float.infinity then Iv.Above_maximum
        else if sigma <= 0.0 then Iv.Below_smallest_volatility
        else root sigma

let sqrt_pi_over_2 = 1.253314137315500251207882642405522626503493370305

(* Mills ratio R(z) = Phi(-z)/phi(z) for z >= 0. *)
let mills z = sqrt_pi_over_2 *. Cody.erfcx_nonnegative (z *. Normal.inv_sqrt_2)

(* Analytic Greeks (FerroRisk conventions: time Greeks are -d/dT per
   calendar day). Each Greek is assembled as an ordinary part plus
   P exp(-(h^2+t^2)/2) 2^k, where the prefactor P collects every algebraic
   factor and k the Greek's degree of homogeneity in (S, K) times the
   coordinate exponent. The exponential, with its exactly split argument, is
   applied last with a single rounding. A tail Greek therefore neither loses
   bits in the subnormals nor underflows before rescaling. Φ enters through
   the Mills ratio, Φ(-z) = φ(z) R(z), so A Φ(θ d1) = A φ(d1) R(-θ d1) shares
   the exponential. Terms in 1/T are rewritten so σ and √T cancel
   analytically, for example vega/(2T) = A φ(d1)/(2 √T). *)
let live_greeks side (c : Coordinates.live) sigma =
  let theta = Side.sign side in
  let e_up = c.exponent and e_down = -c.exponent in
  let up v = Float.ldexp v e_up in
  let q = c.yield and r = c.rate and time = c.time and rt = c.root_time in
  let rt_full = rt *. (1.0 +. (c.root_time_low /. rt)) in
  let dq = Coordinates.exp_neg_product q time in
  let { Dd.hi = s; lo = sl } =
    Dd.mul_float { Dd.hi = rt; lo = c.root_time_low } sigma
  in
  let price = live_price side c sigma in
  let rho_forward () = Ok (-.time *. price) in
  if sigma = 0.0 || (s = 0.0 && c.x <> 0.0) then
    (* Zero variance: the discounted payoff max(θ(A - C), 0). *)
    if c.x = 0.0 then
      {
        Greeks.delta = Greeks.kink;
        gamma = Greeks.kink;
        theta = Greeks.kink;
        vega =
          Ok
            (Units.per_volatility
               (up (c.asset *. rt *. Normalised_black.inv_sqrt_2pi)));
        rho = Greeks.kink;
        vanna = Greeks.kink;
        volga = Ok (Units.per_volatility_squared 0.0);
        charm = Greeks.kink;
        veta = Greeks.kink;
        color = Greeks.kink;
      }
    else
      let itm = theta *. c.x > 0.0 in
      let on v = if itm then v else 0.0 in
      {
        Greeks.delta = Ok (on (theta *. dq));
        gamma = Ok 0.0;
        theta =
          Greeks.daily (up (on (theta *. ((q *. c.asset) -. (r *. c.cash)))));
        vega = Ok (Units.per_volatility 0.0);
        rho =
          (if c.tied then rho_forward ()
           else Ok (up (on (theta *. c.cash *. time))));
        vanna = Ok (Units.per_volatility 0.0);
        volga = Ok (Units.per_volatility_squared 0.0);
        charm = Greeks.daily (on (theta *. q *. dq));
        veta = Greeks.daily 0.0;
        color = Greeks.daily 0.0;
      }
  else
    let hh, hl =
      if s = 0.0 then (0.0, 0.0) else Split.quotient_dd c.x c.x_low s sl
    in
    let t = 0.5 *. s and tl = 0.5 *. sl in
    let e, el = Normalised_black.vega_exponent hh hl t tl in
    (* g ~k p = 2^k p exp(-(h^2 + t^2)/2). *)
    let g ?(k = 0) p = Split.scaled_exp_neg ~k p e el in
    let base =
      Float.sqrt c.asset *. Float.sqrt c.cash *. Normalised_black.inv_sqrt_2pi
      (* A φ(d1) = base G *)
    in
    let spot = c.spot in
    (* d1 = h + t and d2 = h - t in double-double: near a zero of d2 (where
       x = s^2/2) the difference is far below either term. *)
    let dd_sum a al b bl =
      let hi, lo = Split.two_sum a b in
      hi +. (lo +. al +. bl)
    in
    let d1 = dd_sum hh hl t tl and d2 = dd_sum hh hl (-.t) (-.tl) in
    (* Where s is near the bottom of the range, s/2 itself underflows, but
       there h = x/s is either 0 or dominant, so h/σ - √T/2 has no cancellation. *)
    let d2_over_sigma =
      if s < 0x1p-1000 then
        (if c.x = 0.0 then 0.0 else (hh +. hl) /. sigma) -. (0.5 *. rt_full)
      else d2 /. sigma
    in
    (* A Φ(θ d1) and C Φ(θ d2) as ordinary part + Mills part (prefactor of G). *)
    let tail_split leg d =
      if theta *. d <= 0.0 then (0.0, mills (-.theta *. d))
      else (leg, -.mills (theta *. d))
    in
    let a_part, a_mills = tail_split c.asset d1
    and c_part, c_mills = tail_split c.cash d2 in
    (* w = dd1/dT = (2(r-q)T - x + s^2/2)/(2 T s) = (2(r-q)T - x)/(2 T s) + σ/(4 √T),
       in double-double, with d1 likewise: the veta and color brackets
       q + d1 w ∓ 1/(2T) can cancel to far below their terms. *)
    let rt_dd = { Dd.hi = rt; lo = c.root_time_low }
    and s_dd = { Dd.hi = s; lo = sl } in
    let w_dd =
      let carry = Dd.sub (Dd.two_prod r time) (Dd.two_prod q time) in
      let lead =
        Dd.sub (Dd.mul_float carry 2.0) { Dd.hi = c.x; lo = c.x_low }
      in
      let tail = Dd.div (Dd.of_float sigma) (Dd.mul_float rt_dd 4.0) in
      if lead.hi = 0.0 then tail
      else Dd.add (Dd.div lead (Dd.mul_float s_dd (2.0 *. time))) tail
    in
    let w = Dd.to_float w_dd in
    let d1_dd =
      Dd.add
        (Dd.add (Dd.of_float hh) (Dd.of_float hl))
        (Dd.add (Dd.of_float t) (Dd.of_float tl))
    in
    let q_plus_d1_w = Dd.add (Dd.of_float q) (Dd.mul d1_dd w_dd) in
    (* veta's bracket times √T: q √T + √T d1 w - 1/(2 √T), finite even where 1/T is not. *)
    let veta_bracket =
      Dd.to_float
        (Dd.sub (Dd.mul q_plus_d1_w rt_dd) (Dd.div (Dd.of_float 0.5) rt_dd))
    in
    (* color's bracket q + d1 w + 1/(2T); where 1/(2T) overflows, so does color. *)
    let color_bracket =
      let half_inverse_time = 0.5 /. time in
      if Float.is_finite half_inverse_time then
        Dd.to_float
          (Dd.add q_plus_d1_w (Dd.div (Dd.of_float 0.5) (Dd.of_float time)))
      else half_inverse_time
    in
    let day = 1.0 /. Units.days_per_year in
    (* charm = q Δ - D_q φ(d1) w = D_q (θ q Φ(θ d1) - φ(d1) w). Near the money
       the two terms agree to within ~1/80 of their size, more than binary64
       Φ can resolve, so there the bracket is evaluated in double-double;
       in the tails the Mills-ratio form below is already relative. *)
    let charm_dd () =
      let d1_theta = Dd.mul_float d1_dd theta in
      let bracket =
        Dd.sub
          (Dd.mul_float (Normal_dd.cdf d1_theta) (theta *. q))
          (Dd.mul (Normal_dd.pdf d1_dd) w_dd)
      in
      dq *. Dd.to_float bracket *. day
    in
    let delta =
      (theta *. a_part /. spot) +. g (theta *. base *. a_mills /. spot)
    in
    (* theta (annual) = θ(q A Φ(θ d1) - r C Φ(θ d2)) - A φ(d1) σ/(2 √T). Its terms
       cancel near the money and for forward models (q = r), so where |d1| and
       |d2| are at most 6 the whole expression is double-double, legs included. The tails use the
       Mills-ratio form, which is already relative. *)
    let d2_dd = Dd.sub d1_dd s_dd in
    let annual_theta =
      if
        Float.abs d1_dd.Dd.hi <= Normal_dd.limit
        && Float.abs d2_dd.Dd.hi <= Normal_dd.limit
      then
        let asset, cash, _ = precise_legs c in
        let leg leg_dd rate d =
          Dd.mul (Dd.mul_float leg_dd rate)
            (Normal_dd.cdf (Dd.mul_float d theta))
        in
        let carry_terms =
          Dd.mul_float (Dd.sub (leg asset q d1_dd) (leg cash r d2_dd)) theta
        in
        let diffusion =
          Dd.div
            (Dd.mul (Dd.mul asset (Normal_dd.pdf d1_dd)) (Dd.of_float sigma))
            (Dd.mul_float rt_dd 2.0)
        in
        Dd.to_float_scaled (Dd.sub carry_terms diffusion) e_up
      else
        (r *. price)
        +. up (theta *. (q -. r) *. a_part)
        +. g ~k:e_up
             ((theta *. (q -. r) *. base *. a_mills)
             -. (base *. sigma /. (2.0 *. rt_full)))
    in
    let charm =
      if Float.abs d1_dd.Dd.hi <= Normal_dd.limit then charm_dd ()
      else (q *. delta *. day) -. g (base /. spot *. w *. day)
    in
    let rho =
      if c.tied then rho_forward ()
      else
        Ok
          (up (theta *. time *. c_part)
          +. g ~k:e_up (theta *. time *. base *. c_mills))
    in
    {
      Greeks.delta = Ok delta;
      gamma = Ok (g ~k:e_down (base /. (spot *. spot *. s)));
      theta = Ok (Units.per_calendar_day annual_theta);
      vega = Ok (Units.per_volatility (g ~k:e_up (base *. rt_full)));
      rho;
      vanna = Ok (Units.per_volatility (g (-.base /. spot *. d2_over_sigma)));
      volga =
        Ok
          (Units.per_volatility_squared
             (g ~k:e_up (base *. rt_full *. d1 *. d2_over_sigma)));
      charm = Ok (Units.time_rate charm);
      veta = Ok (Units.time_rate (g ~k:e_up (base *. veta_bracket *. day)));
      color =
        Ok
          (Units.time_rate
             (g ~k:e_down (base /. (spot *. spot *. s) *. color_bracket *. day)));
    }

let greeks_coordinates coordinates side sigma =
  match coordinates with
  | Coordinates.Expiry { spot; strike; rate; yield } ->
      Greeks.expiry ~theta:(Side.sign side) ~spot ~strike ~rate ~yield
  | Coordinates.Live c -> live_greeks side c (Vol.to_float sigma)

let implied_coordinates coordinates side price =
  if not (Float.is_finite price && price >= 0.0) then
    invalid Refusal.Price price
  else
    match coordinates with
    | Coordinates.Expiry _ -> Ok Iv.Not_identifiable_at_expiry
    | Coordinates.Live c -> Ok (live_implied side c price)

module Make (C : CARRY) : MODEL with type inputs = C.inputs = struct
  type inputs = C.inputs
  type admitted = Coordinates.t

  let admit = C.coordinates
  let coordinates a = a
  let price a side sigma = price_coordinates a side sigma
  let implied a side price = implied_coordinates a side price
  let greeks a side sigma = greeks_coordinates a side sigma
end

module Bsm_carry = struct
  type inputs = {
    spot : float;
    strike : float;
    time_to_expiry : float;
    rate : float;
    dividend_yield : float;
  }

  let coordinates i =
    if not (positive_finite i.spot) then invalid Refusal.Spot i.spot
    else if not (positive_finite i.strike) then invalid Refusal.Strike i.strike
    else
      Result.map
        (fun () ->
          Coordinates.make ~spot:i.spot ~strike:i.strike ~time:i.time_to_expiry
            ~rate:i.rate ~yield:i.dividend_yield ())
        (Coordinates.validate_carry ~time:i.time_to_expiry ~rate:i.rate
           ~yield:i.dividend_yield ~yield_parameter:Refusal.Dividend_yield)
end

module Bsm = Make (Bsm_carry)

module Black76_carry = struct
  type inputs = {
    forward : float;
    strike : float;
    time_to_expiry : float;
    rate : float;
  }

  let coordinates i =
    if not (positive_finite i.forward) then invalid Refusal.Forward i.forward
    else if not (positive_finite i.strike) then invalid Refusal.Strike i.strike
    else
      Result.map
        (fun () ->
          Coordinates.make ~tied:true ~spot:i.forward ~strike:i.strike
            ~time:i.time_to_expiry ~rate:i.rate ~yield:i.rate ())
        (Coordinates.validate_carry ~time:i.time_to_expiry ~rate:i.rate
           ~yield:i.rate ~yield_parameter:Refusal.Rate)
end

module Black76 = Make (Black76_carry)

module Displaced_carry = struct
  type inputs = {
    forward : float;
    strike : float;
    displacement : float;
    time_to_expiry : float;
    rate : float;
  }

  let coordinates i =
    if not (Float.is_finite i.forward) then invalid Refusal.Forward i.forward
    else if not (Float.is_finite i.strike) then invalid Refusal.Strike i.strike
    else if not (Float.is_finite i.displacement) then
      invalid Refusal.Displacement i.displacement
    else
      match
        Coordinates.validate_carry ~time:i.time_to_expiry ~rate:i.rate
          ~yield:i.rate ~yield_parameter:Refusal.Rate
      with
      | Error _ as e -> e
      | Ok () when i.time_to_expiry = 0.0 ->
          Ok
            (Coordinates.Expiry
               {
                 spot = i.forward;
                 strike = i.strike;
                 rate = i.rate;
                 yield = i.rate;
               })
      | Ok () ->
          (* The shifted coordinates are exact sums, carried as hi + lo. *)
          let f, fl = Split.two_sum i.forward i.displacement
          and k, kl = Split.two_sum i.strike i.displacement in
          if not (positive_finite f) then invalid Refusal.Shifted_forward f
          else if not (positive_finite k) then invalid Refusal.Shifted_strike k
          else
            Ok
              (Coordinates.make ~tied:true ~spot:f ~spot_low:fl ~strike:k
                 ~strike_low:kl ~time:i.time_to_expiry ~rate:i.rate
                 ~yield:i.rate ())
end

module Displaced = Make (Displaced_carry)
