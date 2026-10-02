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
  else if i.time_to_expiry = 0.0 then Ok (Expiry { forward = i.forward; strike = i.strike })
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
  | Expiry { forward; strike } -> Float.max (theta *. (forward -. strike)) 0.0
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
