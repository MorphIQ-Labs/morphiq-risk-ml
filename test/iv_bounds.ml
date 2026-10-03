open Morphiq_risk

(* Conditional error budget for Black roots, composed from normalization
   error and the separately enforced kernel envelope. This is an accuracy
   requirement tested against an independent root, not a convergence theorem
   for Let's Be Rational. No claim that its Newton remainder is below u² is
   needed: [black_interval_bound] uses the minimum vega over the observed
   candidate/reference interval for nonlinear error transport. *)
let black_root_bound model ~side_call ~s ~k ~t ~r ~q ~shift ~quote ~root =
  let u = 0x1p-53 in
  let s', sl = Internal.Split.two_sum s shift
  and k', kl = Internal.Split.two_sum k shift in
  let q' = if model = "bsm" then q else r in
  let x = -.Float.abs (Float.log (s' /. k') +. ((r -. q') *. t)) in
  let sd = root *. Float.sqrt t in
  if not (sd > 0.0 && Float.is_finite sd) then Float.infinity
  else
    let ln_b, bx = Internal.Normalised_black.ln_b_and_scaled x 0.0 sd in
    let c_b = bx /. sd in
    let h = x /. sd and half = 0.5 *. sd in
    let c_bar =
      Internal.Normalised_black.sqrt_two_pi *. 0.5
      *. (Internal.Cody.erfcx ((half +. h) *. Float.sqrt 0.5)
         +. Internal.Cody.erfcx ((half -. h) *. Float.sqrt 0.5))
      /. sd
    in
    (* β = (quote - I⁺)/m: below the money I⁺ = 0; in the money the
       intrinsic's double-word error E_I is divided by quote - I, the
       out-of-the-money part, m b(x, s). *)
    let a = s' *. Float.exp (-.q' *. t) and c = k' *. Float.exp (-.r *. t) in
    let itm = (if side_call then a -. c else c -. a) > 0.0 in
    let otm = Float.sqrt a *. Float.sqrt c *. Float.exp ln_b in
    let d_beta =
      if itm then
        let e_i =
          Bounds.intrinsic_error model ~s ~k ~t ~r ~q ~shift ~reference:0.0
        in
        u +. ((e_i +. (3.0 *. Bounds.u2 *. quote)) /. otm)
      else u
    in
    let linear = (3.0 *. u) +. ((d_beta +. (65.0 *. u)) *. c_b) in
    (* The complement subtracts the quote from a discounted leg, so its
       normalisation error is E_max / (maximum - quote), not E_I / otm.
       Use a lower enclosure for that gap; an unresolved gap is not a
       finite certificate. The tests reject a nonfinite bound. *)
    let coordinate, low, rate =
      if side_call then (s', sl, q') else (k', kl, r)
    in
    let maximum =
      Internal.Dd.mul
        (Internal.Dd.exp (Internal.Dd.neg (Internal.Dd.two_prod rate t)))
        { Internal.Dd.hi = coordinate; lo = low }
    in
    let gap = Internal.Dd.(to_float (sub maximum (of_float quote))) in
    let e_max =
      Float.abs maximum.hi *. (Bounds.eps_exp (rate *. t) +. (5.0 *. Bounds.u2))
    in
    let gap_lower = gap -. e_max -. (2.0 *. u *. Float.abs gap) in
    let normalisation =
      if gap_lower <= 0.0 then Float.infinity
      else
        u +. (e_max /. gap_lower)
        +. Bounds.eps_exp (r *. t)
        +. Bounds.eps_exp (q' *. t)
        +. (32.0 *. Bounds.u2)
    in
    (* erfcx has |d log(erfcx(z))/dz| <= min(2/sqrt(pi), 1/z)
       for z >= 0. Use absolute argument error near z=0, where a
       relative-argument estimate would be invalid. *)
    let dz = 4.0 *. u *. (half +. Float.abs h) *. Float.sqrt 0.5 in
    let sensitivity z =
      if z <= dz then 1.129 else Float.min 1.129 (1.0 /. (z -. dz))
    in
    let argument_error =
      dz
      *. Float.max
           (sensitivity ((half +. h) *. Float.sqrt 0.5))
           (sensitivity ((half -. h) *. Float.sqrt 0.5))
    in
    let exponent = 0.5 *. ((h *. h) +. (half *. half)) in
    let kernel =
      (21.0 *. u) +. argument_error
      +. (Bounds.u2 *. ((16.0 *. exponent) +. (8.0 *. exponent *. exponent)))
    in
    let complement = (3.0 *. u) +. ((normalisation +. kernel) *. c_bar) in
    let logarithmic =
      let exponent = (snd (Float.frexp s') + snd (Float.frexp k')) asr 1 in
      let a = s' *. Float.exp (-.q' *. t) and c = k' *. Float.exp (-.r *. t) in
      let ln_m =
        (0.5 *. (Float.log a +. Float.log c))
        -. (float exponent *. Float.log 2.0)
      in
      let ln_error =
        3.0 *. u
        *. (Float.abs (Float.log quote)
           +. Float.abs (float exponent *. Float.log 2.0)
           +. Float.abs ln_m)
        +. (65.0 *. u)
        +. (2.0 *. u *. Float.abs ln_b)
      in
      (3.0 *. u) +. (ln_error *. c_b)
    in
    let ln_half_max = (0.5 *. x) -. Float.log 2.0
    and ln_small = -900.0 *. Float.log 2.0 in
    (* Within a hair of a threshold the exact β cannot say which branch the
       rounded β took. *)
    let near a b =
      (* log beta changes by at most -log(1-delta_beta). Include the
         log evaluator and the binary64 reconstruction of x. *)
      let delta = d_beta +. (8.0 *. u *. (1.0 +. Float.abs x)) in
      let radius =
        if delta >= 1.0 then Float.infinity
        else -.Float.log1p (-.delta) +. (4.0 *. u *. Float.max 1.0 (Float.abs b))
      in
      Float.abs (a -. b) <= radius
    in
    let candidates =
      (if ln_b > ln_half_max || near ln_b ln_half_max then [ complement ]
       else [])
      @ (if ln_b < ln_small || near ln_b ln_small then [ logarithmic ] else [])
      @
      if
        (ln_b <= ln_half_max && ln_b >= ln_small)
        || near ln_b ln_half_max || near ln_b ln_small
      then [ linear ]
      else []
    in
    List.fold_left Float.max 0.0 candidates

(* Bachelier: transport absolute price error through the minimum vega on
   the interval between the candidate and reference. Vega increases with
   sigma, so the lower endpoint suffices. This is conditional on the 8-ULP
   price envelope, just as Black's linear branch is conditional on 32 ULP.
   A subnormal price contributes an absolute quantum; it must not be replaced
   by u times the quote. No membership in a rounding cell is used. *)
let bachelier_root_bound ~side_call ~s ~k ~t ~r ~quote ~root ~candidate =
  let u = Bounds.u in
  let rt = Float.sqrt t in
  let discount = Float.exp (-.r *. t) in
  let delta =
    Internal.Dd.sub (Internal.Dd.of_float s) (Internal.Dd.of_float k)
  in
  let distance = Float.abs (Internal.Dd.to_float delta) in
  let signed =
    (if side_call then 1.0 else -1.0) *. Internal.Dd.to_float delta
  in
  let intrinsic = Float.max 0.0 (discount *. signed) in
  let vega sigma =
    let d = distance /. (sigma *. rt) in
    discount *. rt *. Float.exp (-0.5 *. d *. d) /. Float.sqrt (2.0 *. Float.pi)
  in
  let lo = Float.min candidate root and hi = Float.max candidate root in
  let vmin = vega lo and vmax = vega hi in
  let otm = Float.max 0.0 (quote -. intrinsic) in
  let e_intrinsic =
    intrinsic *. (Bounds.eps_exp (r *. t) +. (8.0 *. Bounds.u2))
  in
  (* 8 ULP to RN(price) is at most 17u to its exact value. Two more u
     cover rounding the DD discount and the DD out-of-money target.
     8u*sigma is a provisional displacement allowance for stopping and
     conversion, not a proved consequence of the small-step test. A small
     rounded step does not establish a small true residual. Use vmax for
     transporting this assumed displacement. *)
  let e_price = e_intrinsic +. (19.0 *. u *. otm) +. 0x1p-1074 in
  if vmin <= 0.0 then Float.infinity
  else
    ((e_price +. (8.0 *. u *. hi *. vmax)) /. vmin) +. (0.5 *. Bounds.ulp root)

(* b'(s) = phi(0) exp(-(x/s)^2/2-s^2/8) has one maximum.
   Its minimum on any positive interval is at an endpoint. This factor
   replaces linearization at the reference root by the mean-value bound.
   Fail closed if the candidate is outside a numerically resolvable interval. *)
let black_interval_bound model ~side_call ~s ~k ~t ~r ~q ~shift ~quote ~root
    ~candidate =
  let relative =
    black_root_bound model ~side_call ~s ~k ~t ~r ~q ~shift ~quote ~root
  in
  let q = if model = "bsm" then q else r in
  let x = Float.log ((s +. shift) /. (k +. shift)) +. ((r -. q) *. t) in
  let exponent sigma =
    let sd = sigma *. Float.sqrt t in
    (0.5 *. ((x /. sd) ** 2.0)) +. (0.125 *. sd *. sd)
  in
  let amplification =
    Float.exp (Float.max 0.0 (exponent candidate -. exponent root))
  in
  (relative *. root *. amplification) +. (0.5 *. Bounds.ulp root)
