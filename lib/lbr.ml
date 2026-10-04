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

(* Implied normalised Black volatility, after P. Jäckel, "Let's Be Rational"
   (Wilmott, January 2015), following the 2024 reference implementation
   (www.jaeckel.org, LetsBeRational.7z, © 2013-2024 Peter Jäckel; freely
   usable with this notice preserved).

   Given an out-of-the-money normalised price β in (0, b_max) with x <= 0,
   b_max = e^(x/2), solve b(x, s) = β for s. The domain is split at
   s_l < s_c < s_u into four branches. Each branch takes an initial guess
   from a rational cubic interpolation of a transformed objective, then makes
   two Householder steps on an objective chosen so the iteration stays well
   conditioned: 1/ln b in the lowest branch, ln of b_max - b in the highest,
   and b itself between them. *)

let sqrt_pi_over_two = 1.253314137315500251207882642405522626503493370305
let sqrt_two_pi = Normalised_black.sqrt_two_pi
let two_pi = 6.283185307179586476925286766559005768394338798750
let sqrt_three = 1.732050807568877293527446341505872366942805253810
let sqrt_one_over_three = 0.577350269189625764509148780501957455647601751270

let two_pi_over_sqrt_twenty_seven =
  1.209199576156145233729385505094770488189377498728

let sqrt_three_over_third_root_two_pi =
  0.938643487427383566075051356115075878414688769574

let pi_over_six = 0.523598775598298873077107230546583814032861566563
let inv_sqrt_2 = 0.70710678118654752440
let sqrt_dbl_max = Float.sqrt Float.max_float
let iterations = 2

(* Delbourgo and Gregory (1985) shape-preserving rational cubic. *)
module Rational_cubic = struct
  let minimum_parameter = -.(1.0 -. Float.sqrt epsilon_float)
  let maximum_parameter = 2.0 /. (epsilon_float *. epsilon_float)
  let is_zero x = Float.abs x < Float.min_float

  (* [interpolate_t t omt ...] takes t = (x - x_l)/h and omt = 1 - t
     separately, so a caller that knows 1 - t accurately can supply it. *)
  let interpolate_t t omt x_l x_r y_l y_r d_l d_r r =
    let h = x_r -. x_l in
    if Float.abs h <= 0.0 then 0.5 *. (y_l +. y_r)
    else if not (r >= maximum_parameter) then
      let t2 = t *. t and omt2 = omt *. omt in
      ((y_r *. t2 *. t)
      +. (((r *. y_r) -. (h *. d_r)) *. t2 *. omt)
      +. (((r *. y_l) +. (h *. d_l)) *. t *. omt2)
      +. (y_l *. omt2 *. omt))
      /. (1.0 +. ((r -. 3.0) *. t *. omt))
    else (y_r *. t) +. (y_l *. omt)

  let interpolate x x_l x_r y_l y_r d_l d_r r =
    let t = (x -. x_l) /. (x_r -. x_l) in
    interpolate_t t (1.0 -. t) x_l x_r y_l y_r d_l d_r r

  let fit_left x_l x_r y_l y_r d_l d_r second =
    let h = x_r -. x_l in
    let numerator = (0.5 *. h *. second) +. (d_r -. d_l) in
    let denominator = ((y_r -. y_l) /. h) -. d_l in
    if is_zero denominator then
      if numerator > 0.0 then maximum_parameter else minimum_parameter
    else numerator /. denominator

  let fit_right x_l x_r y_l y_r d_l d_r second =
    let h = x_r -. x_l in
    let numerator = (0.5 *. h *. second) +. (d_r -. d_l) in
    let denominator = d_r -. ((y_r -. y_l) /. h) in
    if is_zero denominator then
      if numerator > 0.0 then maximum_parameter else minimum_parameter
    else numerator /. denominator

  let minimum_shape_parameter d_l d_r s prefer_shape =
    let monotonic = d_l *. s >= 0.0 && d_r *. s >= 0.0 in
    let convex = d_l <= s && s <= d_r and concave = d_l >= s && s >= d_r in
    if (not monotonic) && (not convex) && not concave then minimum_parameter
    else
      let d_r_m_d_l = d_r -. d_l
      and d_r_m_s = d_r -. s
      and s_m_d_l = s -. d_l in
      let r1 =
        if monotonic then
          if not (is_zero s) then (d_r +. d_l) /. s
          else if prefer_shape then maximum_parameter
          else -.Float.max_float
        else -.Float.max_float
      in
      let r2 =
        if convex || concave then
          if not (is_zero s_m_d_l || is_zero d_r_m_s) then
            Float.max
              (Float.abs (d_r_m_d_l /. d_r_m_s))
              (Float.abs (d_r_m_d_l /. s_m_d_l))
          else if prefer_shape then maximum_parameter
          else -.Float.max_float
        else if monotonic && prefer_shape then maximum_parameter
        else -.Float.max_float
      in
      Float.max minimum_parameter (Float.max r1 r2)

  let convex_fit_left x_l x_r y_l y_r d_l d_r second prefer_shape =
    Float.max
      (fit_left x_l x_r y_l y_r d_l d_r second)
      (minimum_shape_parameter d_l d_r
         ((y_r -. y_l) /. (x_r -. x_l))
         prefer_shape)

  let convex_fit_right x_l x_r y_l y_r d_l d_r second prefer_shape =
    Float.max
      (fit_right x_l x_r y_l y_r d_l d_r second)
      (minimum_shape_parameter d_l d_r
         ((y_r -. y_l) /. (x_r -. x_l))
         prefer_shape)
end

(* b_l / b_max and b_u / b_max as functions of s_c = sqrt(2|x|) (reference
   four-branch Remez approximations). *)
let b_l_over_b_max s_c =
  if s_c < 2.6267851073127395 then
    if s_c < 0.7099295739719539 then
      let g =
        (8.0741072372882856924e-2
        +. s_c
           *. (9.8078911786358897272e-2
              +. s_c
                 *. (3.9760631445677058375e-2
                    +. s_c
                       *. (5.9716928459589189876e-3
                          +. s_c
                             *. (-6.4036399341479799981e-6
                                +. (4.5425102093616062245e-7 *. s_c))))))
        /. (1.0
           +. s_c
              *. (1.8594977672287664353
                 +. s_c
                    *. (1.3658801475711790419
                       +. s_c
                          *. (4.6132707108655653215e-1
                             +. (6.1254597049831720643e-2 *. s_c)))))
      in
      s_c *. s_c
      *. (0.07560996640296361767172
         +. (s_c *. ((s_c *. g) -. 0.09672719281339436290858)))
    else
      (1.9795737927598581235e-9
      +. s_c
         *. (-2.7081288564685588037e-8
            +. s_c
               *. (7.5610142272549044609e-2
                  +. s_c
                     *. (6.917130174466834016e-2
                        +. s_c
                           *. (2.9537058950963019803e-2
                              +. s_c
                                 *. (6.5849252702302307774e-3
                                    +. (6.9711400639834715731e-4 *. s_c)))))))
      /. (1.0
         +. s_c
            *. (2.1941448525586579756
               +. s_c
                  *. (2.1297103549995181357
                     +. s_c
                        *. (1.1571483187179784072
                           +. s_c
                              *. (3.7831622253060456794e-1
                                 +. s_c
                                    *. (7.1714862448829349869e-2
                                       +. (6.6361975827861200167e-3 *. s_c)))))
               ))
  else if s_c < 7.348469228349534 then
    (-9.3325115354837883291e-5
    +. s_c
       *. (5.3118033972794648837e-4
          +. s_c
             *. (7.4114855448345002595e-2
                +. s_c
                   *. (7.4039658186822817454e-2
                      +. s_c
                         *. (3.9225177407687604785e-2
                            +. s_c
                               *. (1.0022913378254090083e-2
                                  +. (1.7012579407246055469e-3 *. s_c)))))))
    /. (1.0
       +. s_c
          *. (2.2217238132228132256
             +. s_c
                *. (2.3441816707087403282
                   +. s_c
                      *. (1.3912323646271141826
                         +. s_c
                            *. (5.3231258443501838354e-1
                               +. s_c
                                  *. (1.1744005919716101572e-1
                                     +. (1.6195405895930935811e-2 *. s_c)))))))
  else
    (1.4500072297240603183e-3
    +. s_c
       *. (-1.5116692485011195757e-3
          +. s_c
             *. (7.1682178310936334831e-2
                +. s_c
                   *. (3.921610857820463493e-2
                      +. s_c
                         *. (2.9342405658628443931e-2
                            +. s_c
                               *. (5.1832526171631521426e-3
                                  +. (1.6930208078421474854e-3 *. s_c)))))))
    /. (1.0
       +. s_c
          *. (1.6176313502305414664
             +. s_c
                *. (1.6823159175281531664
                   +. s_c
                      *. (8.4878307567372222113e-1
                         +. s_c
                            *. (3.7543742137375791321e-1
                               +. s_c
                                  *. (7.126137099644302999e-2
                                     +. (1.6116992546788676159e-2 *. s_c)))))))

let b_u_over_b_max s_c =
  if s_c < 1.7888543819998317 then
    if s_c < 0.7745966692414833 then
      let g =
        (-6.063099881233561706e-2
        +. s_c
           *. (-8.1011946637120604985e-2
              +. s_c
                 *. (-4.2505564862438753828e-2
                    +. s_c
                       *. (-8.9880000946868691788e-3
                          +. s_c
                             *. (-7.5603072110443268356e-6
                                +. (4.3879556621540147458e-7 *. s_c))))))
        /. (1.0
           +. s_c
              *. (1.8400371530721828756
                 +. s_c
                    *. (1.5709283443886143691
                       +. s_c
                          *. (6.8913245453611400484e-1
                             +. (1.4703173061720980923e-1 *. s_c)))))
      in
      0.7899085945560627246288
      +. (s_c *. s_c *. (0.0614616805805147403487 +. (s_c *. g)))
    else
      (7.8990944435755287611e-1
      +. s_c
         *. (-1.2655410534988972886
            +. s_c
               *. (-2.8803040699221003256
                  +. s_c
                     *. (-2.6936198689113258727
                        +. s_c
                           *. (-1.1213067281643205754
                              +. s_c
                                 *. (-2.1277793801691629892e-1
                                    +. (5.1486445905299802703e-6 *. s_c)))))))
      /. (1.0
         +. s_c
            *. (-1.6021222722060444448
               +. s_c
                  *. (-3.7242680976480704555
                     +. s_c
                        *. (-3.2083117718907365085
                           +. s_c
                              *. (-1.2922333835930958583
                                 -. (2.3762328334050001161e-1 *. s_c))))))
  else if s_c < 6.164414002968976 then
    (7.8990640048967596475e-1
    +. s_c
       *. (1.5993699253596663678
          +. s_c
             *. (1.6481729039140370242
                +. s_c
                   *. (9.8227188109869200166e-1
                      +. s_c
                         *. (3.6313557966186936883e-1
                            +. s_c
                               *. (7.8277036261179606301e-2
                                  +. (9.3404307364538726214e-3 *. s_c)))))))
    /. (1.0
       +. s_c
          *. (2.0247407005640401446
             +. s_c
                *. (2.0087454279103740489
                   +. s_c
                      *. (1.1627561803056961973
                         +. s_c
                            *. (4.2004672123723823581e-1
                               +. s_c
                                  *. (8.9130862793887234546e-2
                                     +. (1.0436767768858021717e-2 *. s_c)))))))
  else
    (7.91133825948419359e-1
    +. s_c
       *. (1.24653733210880042
          +. s_c
             *. (1.32747426980537386
                +. s_c
                   *. (6.95009705717846778e-1
                      +. s_c
                         *. (3.05965944268228457e-1
                            +. s_c
                               *. (6.02200363391352887e-2
                                  +. (1.29050244454344842e-2 *. s_c)))))))
    /. (1.0
       +. s_c
          *. (1.58117486714634672
             +. s_c
                *. (1.60144713247629644
                   +. s_c
                      *. (8.30040185836882436e-1
                         +. s_c
                            *. (3.53071863813401531e-1
                               +. s_c
                                  *. (6.95901684131758475e-2
                                     +. (1.44197580643890011e-2 *. s_c)))))))

(* 1 - erfcx(x), with a Remez rational near 0 to avoid cancellation. *)
let one_minus_erfcx x =
  if x < -1.0 /. 5.0 || x > 1.0 /. 3.0 then 1.0 -. Cody.erfcx x
  else
    x
    *. (1.128379167095512573896
       -. x
          *. (1.0000000000000002
             +. x
                *. (1.1514967181784756
                   +. x
                      *. (5.7689001208873741e-1
                         +. x
                            *. (1.4069188744609651e-1
                               +. (1.4069285713634565e-2 *. x)))))
          /. (1.0
             +. x
                *. (1.9037494962421563
                   +. x
                      *. (1.5089908593742723
                         +. x
                            *. (6.2486081658640257e-1
                               +. x
                                  *. (1.358008134514386e-1
                                     +. (1.2463320728346347e-2 *. x)))))))

(* Exactly at the money b(0, s) = erf(s / sqrt 8); invert with the reference
   Remez rational (accurate to 3.5e-17 on s in [0, 2]) and the project inverse normal beyond. *)
let atm beta beta_bar =
  let beta_max = 0.6826894921370859 in
  if beta <= beta_max then
    let r = (beta_max *. beta_max) -. (beta *. beta) in
    beta
    *. (2.92958954698308816
       +. r
          *. (1.4014698674754995e1
             +. r
                *. (2.44918990556468762e1
                   +. r
                      *. (1.90763928424894996e1
                         +. r
                            *. (6.43250149461895996
                               +. r
                                  *. (7.52328633671821543e-1
                                     +. (1.38781536163865582e-2 *. r)))))))
    /. (1.0
       +. r
          *. (5.22443271807813073
             +. r
                *. (1.02258209975070629e1
                   +. r
                      *. (9.28187483709036392
                         +. r
                            *. (3.9095549184069553
                               +. r
                                  *. (6.61214199809055912e-1
                                     +. (2.89411828874884851e-2 *. r)))))))
  else -2.0 *. Normal.norm_inv (0.5 *. beta_bar)

let householder3 nu h2 h3 =
  (1.0 +. (0.5 *. h2 *. nu)) /. (1.0 +. (nu *. (h2 +. (h3 *. nu /. 6.0))))

let householder4 nu h2 h3 h4 =
  (1.0 +. (nu *. (h2 +. (nu *. h3 /. 6.0))))
  /. (1.0
     +. nu
        *. ((1.5 *. h2)
           +. (nu *. ((h2 *. h2 *. 0.25) +. (h3 /. 3.0) +. (nu *. h4 /. 24.0)))
           ))

let lower_map x s =
  let ax = Float.abs x in
  let z = sqrt_one_over_three *. ax /. s in
  let y = z *. z and s2 = s *. s in
  let phi_cdf = 0.5 *. Cody.erfc (inv_sqrt_2 *. z)
  and phi = Normal.norm_pdf z in
  let fpp =
    pi_over_six *. y /. (s2 *. s) *. phi_cdf
    *. ((8.0 *. sqrt_three *. s *. ax)
       +. (((3.0 *. s2 *. (s2 -. 8.0)) -. (8.0 *. x *. x)) *. phi_cdf /. phi))
    *. Elementary.exp ((2.0 *. y) +. (0.25 *. s2))
  in
  let phi2 = phi_cdf *. phi_cdf in
  let fp = two_pi *. y *. phi2 *. Elementary.exp (y +. (0.125 *. s *. s)) in
  let f = two_pi_over_sqrt_twenty_seven *. ax *. (phi2 *. phi_cdf) in
  (f, fp, fpp)

let inverse_lower_map x f =
  Float.abs
    (x
    /. (sqrt_three
       *. Normal.norm_inv
            (sqrt_three_over_third_root_two_pi *. Elementary.cbrt f
            /. Elementary.cbrt (Float.abs x))))

let upper_map x s =
  let f = 0.5 *. Cody.erfc (0.5 *. inv_sqrt_2 *. s) in
  let w = x /. s *. (x /. s) in
  ( f,
    -0.5 *. Elementary.exp (0.5 *. w),
    sqrt_pi_over_two *. Elementary.exp (w +. (0.125 *. s *. s)) *. w /. s )

let inverse_upper_map f = -2.0 *. Normal.norm_inv f

(* The lowest branch, s < s_l: objective 1/ln b - 1/ln β. *)
let lowest ln_beta x s0 =
  let rec go n s ds =
    if n >= iterations || not (Float.abs ds > epsilon_float *. s) then s
    else
      let bx, ln_vega = Normalised_black.scaled_and_ln_vega x s in
      let ln_b = Elementary.log bx +. ln_vega and bpob = 1.0 /. bx in
      let h = x /. s in
      let x2_over_s3 = h *. h /. s in
      let b_h2 = x2_over_s3 -. (s /. 4.0) in
      let nu = (ln_beta -. ln_b) *. ln_b /. ln_beta /. bpob in
      let lambda = 1.0 /. ln_b in
      let otl = 1.0 +. (2.0 *. lambda) in
      let h2 = b_h2 -. (bpob *. otl) in
      let c = 3.0 *. (x2_over_s3 /. s) in
      let b_h3 = (b_h2 *. b_h2) -. c -. 0.25 in
      let sq_bpob = bpob *. bpob and bppob = b_h2 *. bpob in
      let mu = 6.0 *. lambda *. (1.0 +. lambda) in
      let h3 = b_h3 +. (sq_bpob *. (2.0 +. mu)) -. (bppob *. 3.0 *. otl) in
      let ds =
        if x < -190.0 then
          nu
          *. householder4 nu h2 h3
               ((b_h2 *. (b_h3 -. 0.5))
               -. ((b_h2 -. (2.0 /. s)) *. 2.0 *. c)
               -. bpob
                  *. (sq_bpob
                      *. (6.0
                         +. lambda
                            *. (22.0 +. (lambda *. (36.0 +. (lambda *. 24.0))))
                         )
                     -. (bppob *. (12.0 +. (6.0 *. mu))))
               -. (bppob *. b_h2 *. 3.0 *. otl)
               -. (b_h3 *. bpob *. 4.0 *. otl))
        else nu *. householder3 nu h2 h3
      in
      go (n + 1) (s +. ds) ds
  in
  go 0 s0 Float.max_float

(* The highest branch, s > s_u and β > b_max/2: objective ln(b_max - β) - ln(b_max - b),
   with b_max - b formed without cancellation. *)
let highest beta_bar x s0 =
  let rec go n s ds =
    if n >= iterations || not (Float.abs ds > epsilon_float *. s) then s
    else
      let h = x /. s and t = s /. 2.0 in
      let gp =
        2.0 /. sqrt_two_pi
        /. (Cody.erfcx ((t +. h) *. inv_sqrt_2)
           +. Cody.erfcx ((t -. h) *. inv_sqrt_2))
      in
      let b_bar = Normalised_black.vega x s /. gp in
      let g = Elementary.log (beta_bar /. b_bar) in
      let x2_over_s3 = h *. h /. s in
      let b_h2 = x2_over_s3 -. (s /. 4.0) in
      let c = 3.0 *. (x2_over_s3 /. s) in
      let b_h3 = (b_h2 *. b_h2) -. c -. 0.25 in
      let nu = -.g /. gp and h2 = b_h2 +. gp in
      let h3 = b_h3 +. (gp *. ((2.0 *. gp) +. (3.0 *. b_h2))) in
      let ds =
        if x < -580.0 then
          nu
          *. householder4 nu h2 h3
               ((b_h2 *. (b_h3 -. 0.5))
               -. ((b_h2 -. (2.0 /. s)) *. 2.0 *. c)
               +. gp
                  *. ((6.0 *. gp *. (gp +. (2.0 *. b_h2)))
                     +. (3.0 *. b_h2 *. b_h2)
                     +. (4.0 *. b_h3)))
        else nu *. householder3 nu h2 h3
      in
      go (n + 1) (s +. ds) ds
  in
  go 0 s0 Float.max_float

(* The two middle branches: objective b - β. *)
let middle beta x s0 =
  let rec go n s ds =
    if n >= iterations || not (Float.abs ds > epsilon_float *. s) then s
    else
      let b = Normalised_black.b x s
      and inv_bp = Normalised_black.inv_vega x s in
      let nu = (beta -. b) *. inv_bp and h = x /. s in
      let x2_over_s3 = h *. h /. s in
      let h2 = x2_over_s3 -. (s *. 0.25) in
      let h3 = (h2 *. h2) -. (3.0 *. (x2_over_s3 /. s)) -. 0.25 in
      let ds = nu *. householder3 nu h2 h3 in
      go (n + 1) (s +. ds) ds
  in
  go 0 s0 Float.max_float

(* s with b(x, s) = β, for x <= 0 and 0 < β < e^(x/2). [beta_bar] is
   e^(x/2) - β, supplied by a caller that knows it more accurately than the
   subtraction would give; it decides the highest branch near the maximum.
   [ln_beta] likewise carries ln β where β itself is subnormal. *)
let solve ?beta_bar ?ln_beta beta x =
  let b_max = Elementary.exp (0.5 *. x) in
  let beta_bar = match beta_bar with Some b -> b | None -> b_max -. beta in
  if x = 0.0 then atm beta beta_bar
  else
    let sqrt_ax = Float.sqrt (-.x) in
    let s_c = Float.sqrt 2.0 *. sqrt_ax in
    let ome = one_minus_erfcx sqrt_ax in
    let b_c = 0.5 *. b_max *. ome in
    if beta < b_c then
      let s_l = s_c -. (sqrt_pi_over_two *. ome) in
      let b_l = b_l_over_b_max s_c *. b_max in
      if beta < b_l then
        let f_l, fp_l, fpp_l = lower_map x s_l in
        let r =
          Rational_cubic.convex_fit_right 0.0 b_l 0.0 f_l 1.0 fp_l fpp_l true
        in
        let f = Rational_cubic.interpolate beta 0.0 b_l 0.0 f_l 1.0 fp_l r in
        let f =
          if f > 0.0 then f
          else
            let t = beta /. b_l in
            ((f_l *. t) +. (b_l *. (1.0 -. t))) *. t
        in
        lowest
          (match ln_beta with Some l -> l | None -> Elementary.log beta)
          x (inverse_lower_map x f)
      else
        let inv_v_c = sqrt_two_pi /. b_max
        and inv_v_l = Normalised_black.inv_vega x s_l in
        let r =
          Rational_cubic.convex_fit_right b_l b_c s_l s_c inv_v_l inv_v_c 0.0
            false
        in
        middle beta x
          (Rational_cubic.interpolate beta b_l b_c s_l s_c inv_v_l inv_v_c r)
    else
      let s_u = s_c +. (sqrt_pi_over_two *. (2.0 -. ome)) in
      let b_u = b_u_over_b_max s_c *. b_max in
      if beta <= b_u then
        let inv_v_c = sqrt_two_pi /. b_max
        and inv_v_u = Normalised_black.inv_vega x s_u in
        let r =
          Rational_cubic.convex_fit_left b_c b_u s_c s_u inv_v_c inv_v_u 0.0
            false
        in
        middle beta x
          (Rational_cubic.interpolate beta b_c b_u s_c s_u inv_v_c inv_v_u r)
      else
        let f_u, fp_u, fpp_u = upper_map x s_u in
        (* 1 - t from beta_bar, so a quote near the maximum keeps its distance. *)
        let h = b_max -. b_u in
        let omt = beta_bar /. h in
        let t = 1.0 -. omt in
        let f =
          if fpp_u > -.sqrt_dbl_max && fpp_u < sqrt_dbl_max then
            let r =
              Rational_cubic.convex_fit_left b_u b_max f_u 0.0 fp_u (-0.5) fpp_u
                true
            in
            Rational_cubic.interpolate_t t omt b_u b_max f_u 0.0 fp_u (-0.5) r
          else -.Float.max_float
        in
        let f =
          if f <= 0.0 then ((f_u *. omt) +. (0.5 *. h *. t)) *. omt else f
        in
        let s = inverse_upper_map f in
        if beta > 0.5 *. b_max then highest beta_bar x s else middle beta x s
