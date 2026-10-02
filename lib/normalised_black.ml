(* ======================================================================================
   Portions of this file are derived from "Let's Be Rational", whose reference
   source resides at www.jaeckel.org/LetsBeRational.7z .

   Copyright © 2013-2024 Peter Jäckel.

   Permission to use, copy, modify, and distribute this software is freely granted,
   provided that this notice is preserved.

   WARRANTY DISCLAIMER
   The Software is provided "as is" without warranty of any kind, either express or implied,
   including without limitation any implied warranties of condition, uninterrupted use,
   merchantability, fitness for a particular purpose, or non-infringement.
   ====================================================================================== *)

(* The normalised Black function for an out-of-the-money option,

     b(x, s) = Phi(h + t) exp(x/2) - Phi(h - t) exp(-x/2),
     x <= 0, s > 0, h = x/s, t = s/2,

   after P. Jäckel, "Let's Be Rational" (Wilmott, January 2015), and the
   2024 revision of its reference implementation (www.jaeckel.org,
   LetsBeRational.7z). That revision partitions the domain with η = -13 and
   τ = 2 ε^(1/16) into three regions:

   - Region I: an asymptotic expansion of the scaled function b / vega.
   - Region II: a small-t expansion of the same.
   - Region III: Cody's erfc/erfcx.

   The departure from the reference: in regions I and II the normalised vega
   exp(-(h² + t²)/2) is evaluated with its exponent as an exact unevaluated
   sum, including the remainder of h = x/s, and the prefactor is folded in
   before the exponential. Rounding of the exponent therefore does not grow
   with h², and the result rounds once when it falls into the subnormals. *)

let eta = -13.0
let tau = 2.0 *. Float.sqrt (Float.sqrt (Float.sqrt (Float.sqrt epsilon_float)))
let inv_sqrt_2 = 0.70710678118654752440
let inv_sqrt_2pi = 0.39894228040143267794
let sqrt_pi_over_2 = 1.253314137315500251207882642405522626503493370305

(* Region I: (t/r) * ω with ω the expansion of A(h, t) in q = (h/r)^2, its
   coefficients polynomials in e = (t/h)^2 (reference, A0..A16). *)
module Asymptotic = struct
  (* Generated from the A0..A16 macros of lets_be_rational.cpp (2024). *)
  let a0 _ = 2.0
  let a1 e = -.6. -.2. *. e
  let a2 e = 30. +. e *. (60. +. 6. *. e)
  let a3 e = -.2.1e2 +. e *. (-.1.05e3 +. e *. (-.6.3e2 -.30. *. e))
  let a4 e = 1.89e3 +. e *. (1.764e4 +. e *. (2.646e4 +. e *. (7.56e3 +. 2.1e2 *. e)))
  let a5 e = -.2.079e4 +. e *. (-.3.1185e5 +. e *. (-.8.7318e5 +. e *. (-.6.237e5 +. e *. (-.1.0395e5 -.1.89e3 *. e))))
  let a6 e = 2.7027e5 +. e *. (5.94594e6 +. e *. (2.675673e7 +. e *. (3.567564e7 +. e *. (1.486485e7 +. e *. (1.62162e6 +. 2.079e4 *. e)))))
  let a7 e = -.4.05405e6 +. e *. (-.1.2297285e8 +. e *. (-.8.1162081e8 +. e *. (-.1.73918745e9 +. e *. (-.1.35270135e9 +. e *. (-.3.6891855e8 +. e *. (-.2.837835e7 -.2.7027e5 *. e))))))
  let a8 e = 6.891885e7 +. e *. (2.756754e9 +. e *. (2.50864614e10 +. e *. (7.88431644e10 +. e *. (9.85539555e10 +. e *. (5.01729228e10 +. e *. (9.648639e9 +. e *. (5.513508e8 +. 4.05405e6 *. e)))))))
  let a9 e = -.1.30945815e9 +. e *. (-.6.678236565e10 +. e *. (-.8.013883878e11 +. e *. (-.3.4726830138e12 +. e *. (-.6.3665855253e12 +. e *. (-.5.2090245207e12 +. e *. (-.1.8699062382e12 +. e *. (-.2.671294626e11 +. e *. (-.1.178512335e10 -.6.891885e7 *. e))))))))
  let a10 e = 2.749862115e10 +. e *. (1.7415793395e12 +. e *. (2.664616389435e13 +. e *. (1.52263793682e14 +. e *. (3.848890340295e14 +. e *. (4.618668408354e14 +. e *. (2.664616389435e14 +. e *. (7.10564370516e13 +. e *. (7.83710702775e12 +. e *. (2.749862115e11 +. 1.30945815e9 *. e)))))))))
  let a11 e = -.6.3246828645e11 +. e *. (-.4.870005805665e13 +. e *. (-.9.2530110307635e14 +. e *. (-.6.74147946527055e15 +. e *. (-.2.24715982175685e16 +. e *. (-.3.71802806872497e16 +. e *. (-.3.14602375045959e16 +. e *. (-.1.34829589305411e16 +. e *. (-.2.77590330922905e15 +. e *. (-.2.4350029028325e14 +. e *. (-.6.95715115095e12 -.2.749862115e10 *. e))))))))))
  let a12 e = 1.581170716125e13 +. e *. (1.454677058835e15 +. e *. (3.36030400590885e16 +. e *. (3.04027505296515e17 +. e *. (1.29211689751018875e18 +. e *. (2.81916414002223e18 +. e *. (3.289024830025935e18 +. e *. (2.067387036016302e18 +. e *. (6.8406188691715875e17 +. e *. (1.12010133530295e17 +. e *. (8.0007238235925e15 +. e *. (1.89740485935e14 +. 6.3246828645e11 *. e)))))))))))
  let a13 e = -.4.2691609335375e14 +. e *. (-.4.624924344665625e16 +. e *. (-.1.2764791191277125e18 +. e *. (-.1.40412703104048375e19 +. e *. (-.7.41067044160255312e19 +. e *. (-.2.06151377739125569e20 +. e *. (-.3.17155965752500875e20 +. e *. (-.2.74868503652167425e20 +. e *. (-.1.33392067948845956e20 +. e *. (-.3.51031757760120938e19 +. e *. (-.4.6804234368016125e18 +. e *. (-.2.774954606799375e17 +. e *. (-.5.54990921359875e15 -.1.581170716125e13 *. e))))))))))))
  let a14 e = 1.238056670725875e16 +. e *. (1.5599514051146025e18 +. e *. (5.06984206662245812e19 +. e *. (6.66322100184665925e20 +. e *. (4.27556680951827302e21 +. e *. (1.47701398874267613e22 +. e *. (2.89721974714909549e22 +. e *. (3.31110828245610914e22 +. e *. (2.2155209831140142e22 +. e *. (8.55113361903654604e21 +. e *. (1.83238577550783129e21 +. e *. (2.02793682664898325e20 +. e *. (1.01396841332449162e19 +. e *. (1.733279339016225e17 +. 4.2691609335375e14 *. e)))))))))))))
  let a15 e = -.3.8379756792502125e17 +. e *. (-.5.56506473491280812e19 +. e *. (-.2.10359446979704147e21 +. e *. (-.3.25556286992399275e22 +. e *. (-.2.49593153360839444e23 +. e *. (-.1.04829124411552567e24 +. e *. (-.2.55352995361474201e24 +. e *. (-.3.72085793241005264e24 +. e *. (-.3.28310994036181115e24 +. e *. (-.1.74715207352587611e24 +. e *. (-.5.49104937393846778e23 +. e *. (-.9.76668860977197826e22 +. e *. (-.9.11557603578717971e21 +. e *. (-.3.89554531443896569e20 +. e *. (-.5.75696351887531875e18 -.1.238056670725875e16 *. e))))))))))))))
  let a16 e = 1.26653197415257012e19 +. e *. (2.09399953059891594e21 +. e *. (9.10889795810528434e22 +. e *. (1.63960163245895118e24 +. e *. (1.48019591819210871e25 +. e *. (7.42789224401858187e25 +. e *. (2.19979885688242617e26 +. e *. (3.98058840769200926e26 +. e *. (4.47816195865351041e26 +. e *. (3.1425697955463231e26 +. e *. (1.36178024473674001e26 +. e *. (3.55247020366106089e25 +. e *. (5.32870530549159134e24 +. e *. (4.25081904711579936e23 +. e *. (1.57049964794918696e22 +. e *. (2.0264511586441122e20 +. 3.8379756792502125e17 *. e)))))))))))))))

  (* Highest-order term first; the reference adds terms beyond A4 according to
     the distance -h - t + τ + 1/2 from the region's upper border. *)
  let high_terms = [| a16; a15; a14; a13; a12; a11; a10; a9; a8; a7; a6; a5 |]

  let thresholds =
    [| 12.347; 12.958; 13.729; 14.718; 16.016; 17.769; 20.221; 23.816; 29.419; 38.93; 57.171; 99.347 |]

  (* Index of the first threshold above v (std::upper_bound). *)
  let upper_bound v =
    let n = Array.length thresholds in
    let rec go i = if i < n && thresholds.(i) <= v then go (i + 1) else i in
    go 0

  (* The scaled function b / vega. *)
  let scaled h t =
    let e = (t /. h) *. (t /. h) in
    let r = (h +. t) *. (h -. t) in
    let q = (h /. r) *. (h /. r) in
    let omega = ref 0.0 in
    for i = upper_bound (-.h -. t +. tau +. 0.5) to Array.length high_terms - 1 do
      omega := q *. (high_terms.(i) e +. !omega)
    done;
    let omega = a0 e +. (q *. (a1 e +. (q *. (a2 e +. (q *. (a3 e +. (q *. (a4 e +. !omega)))))))) in
    t /. r *. omega
end

(* Y'(h) = 1 + h Y(h), Y = Phi / phi, for h <= 0 without cancellation
   (reference Remez rational approximations below -0.46875). *)
let y_prime h =
  if h < -4.0 then
    let w = 1.0 /. (h *. h) in
    let g =
      w
      *. (-2.9999999999994663866
         +. w
            *. (-1.7556263323542206288e2
               +. (w *. (-3.4735035445495633334e3 +. (w *. (-2.7805745693864308643e4 +. (w *. (-8.3836021460741980839e4 -. (6.6818249032616849037e4 *. w)))))))))
      /. (1.0
         +. w
            *. (6.3520877744831739102e1
               +. (w *. (1.4404389037604337538e3 +. (w *. (1.4562545638507033944e4 +. (w *. (6.6886794165651675684e4 +. (w *. (1.2569970380923908488e5 +. (6.9286518679803751694e4 *. w)))))))))))
    in
    w *. (1.0 +. g)
  else if h <= -0.46875 then
    (1.0000000000594317229
    -. h
       *. (6.1911449879694112749e-1
          -. h
             *. (2.2180844736576013957e-1
                -. h
                   *. (4.5650900351352987865e-2
                      -. (h *. (5.545521007735379052e-3 -. (h *. (3.0717392274913902347e-4 -. (h *. (4.2766597835908713583e-8 +. (8.4592436406580605619e-10 *. h)))))))))))
    /. (1.0
       -. h
          *. (1.8724286369589162071
             -. h
                *. (1.5685497236077651429
                   -. h
                      *. (7.6576489836589035112e-1
                         -. (h *. (2.3677701403094640361e-1 -. (h *. (4.6762548903194957675e-2 -. (h *. (5.5290453576936595892e-3 -. (3.0822020417927147113e-4 *. h)))))))))))
  else 1.0 +. (h *. sqrt_pi_over_2 *. Cody.erfcx (-.inv_sqrt_2 *. h))

(* Region II: the scaled function to twelfth order in t (reference B0..B6). *)
let small_t_scaled h t =
  let a = y_prime h and h2 = h *. h and t2 = t *. t in
  let b0 = 2.0 *. a in
  let b1 = (-1.0 +. (a *. (3.0 +. h2))) /. 3.0 in
  let b2 = (-7.0 -. h2 +. (a *. (15.0 +. (h2 *. (10.0 +. h2))))) /. 60.0 in
  let b3 = (-57.0 +. ((-18.0 -. h2) *. h2) +. (a *. (105.0 +. (h2 *. (105.0 +. (h2 *. (21.0 +. h2))))))) /. 2520.0 in
  let b4 =
    (-561.0
    +. (h2 *. (-285.0 +. ((-33.0 -. h2) *. h2)))
    +. (a *. (945.0 +. (h2 *. (1260.0 +. (h2 *. (378.0 +. (h2 *. (36.0 +. h2)))))))))
    /. 181440.0
  in
  let b5 =
    (-6555.0
    +. (h2 *. (-4680.0 +. (h2 *. (-840.0 +. ((-52.0 -. h2) *. h2)))))
    +. (a *. (10395.0 +. (h2 *. (17325.0 +. (h2 *. (6930.0 +. (h2 *. (990.0 +. (h2 *. (55.0 +. h2)))))))))))
    /. 19958400.0
  in
  let b6 =
    (-89055.0
    +. (h2 *. (-82845.0 +. (h2 *. (-20370.0 +. (h2 *. (-1926.0 +. ((-75.0 -. h2) *. h2)))))))
    +. a
       *. (135135.0 +. (h2 *. (270270.0 +. (h2 *. (135135.0 +. (h2 *. (25740.0 +. (h2 *. (2145.0 +. (h2 *. (78.0 +. h2)))))))))))
    )
    /. 3113510400.0
  in
  t *. (b0 +. (t2 *. (b1 +. (t2 *. (b2 +. (t2 *. (b3 +. (t2 *. (b4 +. (t2 *. (b5 +. (b6 *. t2))))))))))))

(* exp(-(h^2 + t^2)/2) as an unevaluated sum, with h = hh + hl. *)
let vega_exponent hh hl t tl =
  let h2, h2l = Split.square hh in
  let t2, t2l = Split.square t in
  let s, sl = Split.two_sum h2 t2 in
  (0.5 *. s, 0.5 *. (sl +. h2l +. t2l +. (2.0 *. hh *. hl) +. (2.0 *. t *. tl)))

(* Region III with Cody's functions, choosing per term between erfc and
   erfcx to minimise exponentials (reference, 2017-02-18). *)
let with_cody x xl s sl =
  let hh, hl = Split.quotient_dd x xl s sl in
  let h = hh +. hl and t = 0.5 *. s in
  let half_exp sign = Float.exp (sign *. 0.5 *. x) *. (1.0 +. (sign *. 0.5 *. xl)) in
  let q1 = -.inv_sqrt_2 *. (h +. t) and q2 = -.inv_sqrt_2 *. (h -. t) in
  let gauss () =
    let e, el = vega_exponent hh hl t (0.5 *. sl) in
    Split.scaled_exp_neg 1.0 e el
  in
  let two_b =
    if q1 < Cody.thresh then
      if q2 < Cody.thresh then (half_exp 1.0 *. Cody.erfc q1) -. (half_exp (-1.0) *. Cody.erfc q2)
      else (half_exp 1.0 *. Cody.erfc q1) -. (gauss () *. Cody.erfcx_nonnegative q2)
    else if q2 < Cody.thresh then (gauss () *. Cody.erfcx_nonnegative q1) -. (half_exp (-1.0) *. Cody.erfc q2)
    else gauss () *. (Cody.erfcx_nonnegative q1 -. Cody.erfcx_nonnegative q2)
  in
  Float.max (0.5 *. two_b) 0.0

let region_i x s = x < s *. eta && (s *. ((0.5 *. s) -. (tau +. 0.5 +. eta))) +. x < 0.0
let region_ii x s = (s *. (s -. (2.0 *. tau))) -. (x /. eta) < 0.0

let scaled ?(k = 0) m x xl s sl =
  let expansion scaled_fn =
    let hh, hl = Split.quotient_dd x xl s sl in
    let t = 0.5 *. s in
    let e, el = vega_exponent hh hl t (0.5 *. sl) in
    Split.scaled_exp_neg ~k (m *. inv_sqrt_2pi *. scaled_fn hh t) e el
  in
  if x = 0.0 then
    (* At the money b = 2 Phi(s/2) - 1 = erf(s / sqrt 8). *)
    Float.ldexp (m *. Cody.erf (0.5 *. inv_sqrt_2 *. s)) k
  else if region_i x s then expansion Asymptotic.scaled
  else if region_ii x s then expansion small_t_scaled
  else Float.ldexp (m *. with_cody x xl s sl) k

let ln_two_pi = 1.8378770664093454835606594728112352797227949472755668
let sqrt_two_pi = 2.506628274631000502415765284811045253006986740609938316629923576

(* b(x, s) for x <= 0, s > 0, without extended inputs. *)
let b x s = scaled 1.0 x 0.0 s 0.0

(* ln of the normalised vega exp(-(h^2 + t^2)/2) / sqrt(2 pi). *)
let ln_vega x s =
  let h = x /. s and t = 0.5 *. s in
  (-.0.5 *. ln_two_pi) -. (0.5 *. ((h *. h) +. (t *. t)))

let vega x s = Float.exp (ln_vega x s)
let inv_vega x s = sqrt_two_pi *. Float.exp (0.5 *. (((x /. s) *. (x /. s)) +. (0.25 *. s *. s)))

(* (b / vega, ln vega), the scaled function and its scale (reference
   scaled_normalised_black_and_ln_vega). *)
let scaled_and_ln_vega x s =
  let lv = ln_vega x s in
  if region_i x s then (Asymptotic.scaled (x /. s) (0.5 *. s), lv)
  else if region_ii x s then (small_t_scaled (x /. s) (0.5 *. s), lv)
  else (with_cody x 0.0 s 0.0 *. Float.exp (-.lv), lv)

(* b_max - b = (erfcx((t+h)/sqrt 2) + erfcx((t-h)/sqrt 2)) / 2 * exp(-(h^2+t^2)/2),
   free of cancellation (reference complementary_normalised_black), with
   h = x/s carried to double-double and the exponent split exactly. *)
let complement x xl s sl =
  let hh, hl = Split.quotient_dd x xl s sl in
  let t = 0.5 *. s in
  let h = hh +. hl in
  let e, el = vega_exponent hh hl t (0.5 *. sl) in
  Split.scaled_exp_neg (0.5 *. (Cody.erfcx ((t +. h) *. inv_sqrt_2) +. Cody.erfcx ((t -. h) *. inv_sqrt_2))) e el

