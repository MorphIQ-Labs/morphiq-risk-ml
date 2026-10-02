(* The normal (Bachelier) model on a forward, with volatility in price units:

     V = D [ θ (F - K) Φ(θ d) + s φ(d) ],  s = σ √T,  d = (F - K) / s.

   The out-of-the-money part is D s φ(d) Y'(-|d|), where Y'(h) = 1 + h Φ(h)/φ(h)
   is Jäckel's cancellation-free form of φ(d) - |d| Φ(-|d|). *)

let inv_sqrt_2pi = 0.39894228040143267794

type inputs = { forward : float; strike : float; time_to_expiry : float; rate : float }

type coordinates =
  | Expiry of { forward : float; strike : float }
  | Live of {
      discount : float;
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
  else if i.time_to_expiry = 0.0 then Ok (Expiry { forward = i.forward; strike = i.strike })
  else
    let distance, distance_low = Split.two_sum i.forward (-.i.strike) in
    Ok
      (Live
         {
           discount = Black.Coordinates.exp_neg_product i.rate i.time_to_expiry;
           distance;
           distance_low;
           time = i.time_to_expiry;
           root_time = fst (Split.sqrt i.time_to_expiry);
           root_time_low = snd (Split.sqrt i.time_to_expiry);
         })


let price a side sigma =
  let theta = Side.sign side in
  match a with
  | Expiry { forward; strike } -> Float.max (theta *. (forward -. strike)) 0.0
  | Live { discount; distance; distance_low; root_time; root_time_low; _ } ->
      let delta = theta *. distance and delta_low = theta *. distance_low in
      let intrinsic = if delta > 0.0 || (delta = 0.0 && delta_low > 0.0) then (discount *. delta) +. (discount *. delta_low) else 0.0 in
      let { Dd.hi = s; lo = sl } = Dd.mul_float { Dd.hi = root_time; lo = root_time_low } (Vol.to_float sigma) in
      if s = 0.0 then intrinsic
      else
        (* d = |Δ| / s carried as q + r, so d²/2 is formed without rounding. *)
        let abs_low = if distance < 0.0 then -.distance_low else distance_low in
        let q, r = Split.quotient_dd (Float.abs distance) abs_low s sl in
        let q2, q2l = Split.square q in
        let m = discount *. s *. inv_sqrt_2pi *. Normalised_black.y_prime (-.(q +. r)) in
        intrinsic +. Split.scaled_exp_neg m (0.5 *. q2) ((0.5 *. q2l) +. (q *. r))
