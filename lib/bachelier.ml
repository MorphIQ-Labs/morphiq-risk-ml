(* The normal (Bachelier) model on a forward, with volatility in price units:

     V = D [ θ (F - K) Φ(θ d) + s φ(d) ],  s = σ √T,  d = (F - K) / s.

   The out-of-the-money part is D s φ(d) Y'(-|d|), where Y'(h) = 1 + h Φ(h)/φ(h)
   is Jäckel's cancellation-free form of φ(d) - |d| Φ(-|d|). *)

let inv_sqrt_2pi = 0.39894228040143267794

type inputs = { forward : float; strike : float; time_to_expiry : float; rate : float }

type coordinates =
  | Expiry of { forward : float; strike : float; rate : float }
  | Live of {
      discount : float;
      rate : float;
      distance : float;
      distance_low : float;
      time : float;
      root_time : float;
      root_time_low : float;
    }

type admitted = coordinates

let invalid parameter value = Error (Refusal.Invalid_input { parameter; value })

let admit i =
  if not (Float.is_finite i.forward) then invalid Refusal.Forward i.forward
  else if not (Float.is_finite i.strike) then invalid Refusal.Strike i.strike
  else if not (Float.is_finite i.time_to_expiry && i.time_to_expiry >= 0.0) then
    invalid Refusal.Time_to_expiry i.time_to_expiry
  else if not (Float.is_finite i.rate) then invalid Refusal.Rate i.rate
  else if i.time_to_expiry = 0.0 then Ok (Expiry { forward = i.forward; strike = i.strike; rate = i.rate })
  else
    let distance, distance_low = Split.two_sum i.forward (-.i.strike) in
    Ok
      (Live
         {
           discount = Black.Coordinates.exp_neg_product i.rate i.time_to_expiry;
           rate = i.rate;
           distance;
           distance_low;
           time = i.time_to_expiry;
           root_time = fst (Split.sqrt i.time_to_expiry);
           root_time_low = snd (Split.sqrt i.time_to_expiry);
         })


(* D s φ(d) Y'(-d) with d = |Δ| / s, the out-of-the-money part, for s > 0.
   d is carried as q + r so d²/2 is formed without rounding. *)
let otm ~discount ~abs_distance ~abs_low s sl =
  let q, r = Split.quotient_dd abs_distance abs_low s sl in
  let q2, q2l = Split.square q in
  let m = discount *. s *. inv_sqrt_2pi *. Normalised_black.y_prime (-.(q +. r)) in
  Split.scaled_exp_neg m (0.5 *. q2) ((0.5 *. q2l) +. (q *. r))

let abs_parts distance distance_low =
  if distance < 0.0 then (-.distance, -.distance_low) else (distance, distance_low)

let price a side sigma =
  let theta = Side.sign side in
  match a with
  | Expiry { forward; strike; _ } -> Float.max (theta *. (forward -. strike)) 0.0
  | Live { discount; distance; distance_low; root_time; root_time_low; _ } ->
      let delta = theta *. distance and delta_low = theta *. distance_low in
      let intrinsic =
        if delta > 0.0 || (delta = 0.0 && delta_low > 0.0) then (discount *. delta) +. (discount *. delta_low) else 0.0
      in
      let { Dd.hi = s; lo = sl } = Dd.mul_float { Dd.hi = root_time; lo = root_time_low } (Vol.to_float sigma) in
      if s = 0.0 then intrinsic
      else
        let abs_distance, abs_low = abs_parts distance distance_low in
        intrinsic +. otm ~discount ~abs_distance ~abs_low s sl

let sqrt_two_pi = Normalised_black.sqrt_two_pi

(* s with otm(s) = target. otm is increasing with slope D φ(d), between the
   bounds s/sqrt(2π) - |Δ| <= otm/D <= s/sqrt(2π), so the root lies in
   [β sqrt(2π), (β + |Δ|) sqrt(2π)] for β = target/D. Newton on ln otm(s),
   falling back to bisection whenever a step leaves the bracket. *)
let solve_total_volatility ~discount ~abs_distance ~abs_low target =
  let beta = target /. discount in
  if abs_distance = 0.0 then beta *. sqrt_two_pi
  else
    let f s = otm ~discount ~abs_distance ~abs_low s 0.0 in
    let rec go n lo hi s =
      let v = f s in
      if n >= 200 || v = target then s
      else
        let lo, hi = if v < target then (s, hi) else (lo, s) in
        let d = abs_distance /. s in
        let slope = discount *. Normal.norm_pdf d in
        let step = (Float.log target -. Float.log v) *. v /. slope in
        let next = s +. step in
        let next = if next > lo && next < hi && Float.is_finite next then next else 0.5 *. (lo +. hi) in
        if Float.abs (next -. s) <= epsilon_float *. s || hi -. lo <= epsilon_float *. hi then next
        else go (n + 1) lo hi next
    in
    let lo = beta *. sqrt_two_pi and hi = (beta +. abs_distance) *. sqrt_two_pi in
    go 0 lo hi (Float.sqrt lo *. Float.sqrt hi)

let root sigma = match Vol.normal sigma with Ok v -> Iv.Root v | Error _ -> Iv.Above_maximum

let implied a side price =
  if not (Float.is_finite price && price >= 0.0) then
    Error (Refusal.Invalid_input { parameter = Refusal.Price; value = price })
  else
    match a with
    | Expiry _ -> Ok Iv.Not_identifiable_at_expiry
    | Live { distance; distance_low; time; root_time; root_time_low; rate; _ } ->
        let theta = Side.sign side in
        (* The zero-volatility price D θ Δ in double-double. *)
        let discount_dd = Dd.exp (Dd.neg (Dd.two_prod rate time)) in
        let delta = Dd.mul_float { Dd.hi = distance; lo = distance_low } theta in
        let intrinsic = Dd.mul discount_dd delta in
        if intrinsic.hi > 0.0 && Dd.compare_float intrinsic price > 0 then
          Ok (if price = intrinsic.hi then root 0.0 else Iv.Below_intrinsic)
        else
          let otm_target = Dd.sub (Dd.of_float price) (if intrinsic.hi > 0.0 then intrinsic else Dd.of_float 0.0) in
          if otm_target.hi = 0.0 then Ok (root 0.0)
          else
            let abs_distance, abs_low = abs_parts distance distance_low in
            let s =
              solve_total_volatility ~discount:(Dd.to_float discount_dd) ~abs_distance ~abs_low (Dd.to_float otm_target)
            in
            let sigma = s /. root_time *. (1.0 -. (root_time_low /. root_time)) in
            Ok
              (if Float.is_nan sigma || sigma = Float.infinity then Iv.Above_maximum
               else if sigma <= 0.0 then Iv.Below_smallest_volatility
               else root sigma)

let sqrt_pi_over_2 = 1.253314137315500251207882642405522626503493370305
let mills z = sqrt_pi_over_2 *. Cody.erfcx_nonnegative (z *. Normal.inv_sqrt_2)

(* Analytic Greeks on the forward, with D = e^(-rT), s = σ √T and
   d = (F - K)/s carried in double-double:
   Δ = θ D Φ(θ d), Γ = D φ(d)/s, vega = D φ(d) √T, ρ = -T V,
   vanna = -D φ(d) d/σ, volga = vega d²/σ,
   and the time Greeks (-d/dT, per calendar day):
   Θ = r V - D φ(d) σ/(2 √T), charm = r Δ + D φ(d) d/(2T),
   veta = vega (r - (1 + d²)/(2T)), color = Γ (r + (1 - d²)/(2T)).
   As in the Black family, each is an ordinary part plus P exp(-d²/2) with
   the exponential applied last, and Φ(θ d) enters through the Mills ratio. *)
let greeks a side sigma =
  let theta = Side.sign side in
  let sigma_f = Vol.to_float sigma in
  match a with
  | Expiry { forward; strike; rate } -> Greeks.expiry ~theta ~spot:forward ~strike ~rate ~yield:rate
  | Live { discount; distance; distance_low; time; root_time; root_time_low; rate; _ } ->
      let value = price a side sigma in
      let rho = Ok (-.time *. value) in
      let rt = root_time *. (1.0 +. (root_time_low /. root_time)) in
      let { Dd.hi = s; lo = sl } = Dd.mul_float { Dd.hi = root_time; lo = root_time_low } sigma_f in
      let day = 1.0 /. Units.days_per_year in
      if sigma_f = 0.0 || (s = 0.0 && distance <> 0.0) then
        if distance = 0.0 && distance_low = 0.0 then
          {
            Greeks.delta = Greeks.kink;
            gamma = Greeks.kink;
            theta = Greeks.kink;
            vega = Ok (Units.per_volatility (discount *. rt *. inv_sqrt_2pi));
            rho = Greeks.kink;
            vanna = Greeks.kink;
            volga = Ok (Units.per_volatility_squared 0.0);
            charm = Greeks.kink;
            veta = Greeks.kink;
            color = Greeks.kink;
          }
        else
          let itm = theta *. distance > 0.0 in
          let delta = if itm then theta *. discount else 0.0 in
          {
            Greeks.delta = Ok delta;
            gamma = Ok 0.0;
            theta = Greeks.daily (rate *. value);
            vega = Ok (Units.per_volatility 0.0);
            rho;
            vanna = Ok (Units.per_volatility 0.0);
            volga = Ok (Units.per_volatility_squared 0.0);
            charm = Greeks.daily (rate *. delta);
            veta = Greeks.daily 0.0;
            color = Greeks.daily 0.0;
          }
      else
        let dh, dl = if s = 0.0 then (0.0, 0.0) else Split.quotient_dd distance distance_low s sl in
        let d = dh +. dl in
        let d2h, d2l = Split.square dh in
        let g p = Split.scaled_exp_neg p (0.5 *. d2h) ((0.5 *. d2l) +. (dh *. dl)) in
        let base = discount *. inv_sqrt_2pi (* D φ(d) = base G *) in
        (* d/σ, kept finite where s underflows at the money. *)
        let d_over_sigma = if distance = 0.0 && distance_low = 0.0 then 0.0 else d /. sigma_f in
        (* veta's and color's brackets cancel where d^2 = 1 ± 2rT: both in
           double-double, with d = dh + dl and √T's low part. *)
        let d2_dd = Dd.mul { Dd.hi = dh; lo = dl } { Dd.hi = dh; lo = dl } in
        let rt_dd = { Dd.hi = root_time; lo = root_time_low } in
        let veta_bracket =
          Dd.to_float
            (Dd.sub (Dd.mul_float rt_dd rate) (Dd.div (Dd.add (Dd.of_float 1.0) d2_dd) (Dd.mul_float rt_dd 2.0)))
        in
        let color_bracket =
          let half_inverse_time = 0.5 /. time in
          if Float.is_finite half_inverse_time then
            Dd.to_float (Dd.add (Dd.of_float rate) (Dd.div (Dd.sub (Dd.of_float 1.0) d2_dd) (Dd.of_float (2.0 *. time))))
          else (1.0 -. (d *. d)) *. half_inverse_time
        in
        (* charm = r Δ + D φ(d) d/(2T) = D (θ r Φ(θ d) + φ(d) d/(2T)): the
           terms cancel near the money, so there the bracket is double-double. *)
        let charm_dd () =
          let d_dd = { Dd.hi = dh; lo = dl } in
          let bracket =
            Dd.add
              (Dd.mul_float (Normal_dd.cdf (Dd.mul_float d_dd theta)) (theta *. rate))
              (Dd.div (Dd.mul (Normal_dd.pdf d_dd) d_dd) (Dd.of_float (2.0 *. time)))
          in
          discount *. Dd.to_float bracket *. day
        in
        let delta =
          if theta *. d <= 0.0 then theta *. g (base *. mills (-.theta *. d))
          else theta *. (discount -. g (base *. mills (theta *. d)))
        in
        let charm =
          if Float.abs dh <= Normal_dd.limit && Float.is_finite (0.5 /. time) then charm_dd ()
          else (rate *. delta *. day) +. g (base *. d /. (2.0 *. time) *. day)
        in
        {
          Greeks.delta = Ok delta;
          gamma = Ok (g (base /. s));
          theta = Ok (Units.per_calendar_day ((rate *. value) -. g (base *. sigma_f /. (2.0 *. rt))));
          vega = Ok (Units.per_volatility (g (base *. rt)));
          rho;
          vanna = Ok (Units.per_volatility (g (-.base *. d_over_sigma)));
          volga = Ok (Units.per_volatility_squared (g (base *. rt *. d *. d_over_sigma)));
          charm = Ok (Units.time_rate charm);
          veta = Ok (Units.time_rate (g (base *. veta_bracket *. day)));
          color = Ok (Units.time_rate (g (base /. s *. color_bracket *. day)));
        }
