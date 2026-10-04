(* Error propagation for the actual arithmetic paths. A ball encloses the
   mathematical value represented by its computed centre. Every radius
   operation rounds outwards. No observed discrepancy determines a radius.
   Replays must agree bit for bit with the served result before their radius
   is accepted. Unsupported exponent/domain cases are explicit, never passes. *)
open Morphiq_risk
open Internal
module Dd = Checked_dd
module Normal_dd = Checked_normal_dd

exception Unsupported of string

let require condition why = if not condition then raise (Unsupported why)

let require_replay condition why =
  require ((not Certificate_mode.require_replay) || condition) why

let quantum = 0x1p-1074
let up x = Float.next_after x Float.infinity
let down x = Float.next_after x Float.neg_infinity
let ( +^ ) a b = if a = 0.0 && b = 0.0 then 0.0 else up (a +. b)
let ( *^ ) a b = if a = 0.0 || b = 0.0 then 0.0 else up (a *. b)
let ( /^ ) a b = if a = 0.0 then 0.0 else up (a /. b)
let abs = Float.abs
let round v = Float.max quantum (0.5 *. Bounds.ulp v)

type t = { v : float; e : float }

let replay_matches got b =
  (not Certificate_mode.require_replay)
  || Int64.bits_of_float got = Int64.bits_of_float b.v

let ball v e =
  require (Float.is_finite v && Float.is_finite e && e >= 0.0) "nonfinite ball";
  { v; e }

let exact v = ball v 0.0
let magnitude a = abs a.v +^ a.e
let neg a = { a with v = -.a.v }

let add a b =
  let v = a.v +. b.v in
  ball v (a.e +^ b.e +^ round v)

let sub a b = add a (neg b)

let mul a b =
  let v = a.v *. b.v in
  ball v ((abs a.v *^ b.e) +^ (magnitude b *^ a.e) +^ round v)

let div a b =
  let lower = down (abs b.v -. b.e) in
  require (lower > 0.0) "division interval contains zero";
  let v = a.v /. b.v in
  ball v (((a.e +^ ((abs v +^ round v) *^ b.e)) /^ lower) +^ round v)

let c x = exact x
let constant x = ball x (round x)
let mulf a b = mul a (c b)
let divf a b = div a (c b)
let day = div (c 1.0) (c 365.0)

module D = struct
  type t = { v : Dd.t; e : float }

  let magnitude a = abs a.v.Dd.hi +^ abs a.v.lo

  let make v e =
    require
      (Float.is_finite v.Dd.hi && Float.is_finite v.lo && Float.is_finite e
     && e >= 0.0)
      "invalid DD ball";
    require (v.hi +. v.lo = v.hi) "DD words violate nonoverlap";
    { v; e }

  let of_float v = make (Dd.of_float v) 0.0
  let input hi lo e = make { Dd.hi; lo } e
  let neg a = { a with v = Dd.neg a.v }

  (* Every executed primitive checks this fixed finite-exponent allowance
     with exact rationals in Checked_dd. This is a per-input witness, not a
     universal extension of the published unbounded-exponent theorems. *)
  let rounding v eps =
    let m = abs v.Dd.hi +^ abs v.lo in
    (eps *^ m /^ down (1.0 -. eps)) +^ (32.0 *. quantum)

  let add a b =
    let v = Dd.add a.v b.v in
    make v
      (a.e +^ b.e
      +^ rounding v (up ((3.0 *. Bounds.u2) +. (13.0 *. Bounds.u2 *. Bounds.u)))
      )

  let sub a b = add a (neg b)

  let mul a b =
    let v = Dd.mul a.v b.v in
    make v
      ((magnitude a *^ b.e)
      +^ ((magnitude b +^ b.e) *^ a.e)
      +^ rounding v (5.0 *. Bounds.u2))

  let mulf a x =
    let v = Dd.mul_float a.v x in
    make v ((abs x *^ a.e) +^ rounding v (2.0 *. Bounds.u2))

  let div a b =
    let lower = down (down (abs b.v.hi -. abs b.v.lo) -. b.e) in
    require (lower > 0.0) "DD denominator interval contains zero";
    let v = Dd.div a.v b.v in
    let er = rounding v (9.8 *. Bounds.u2) in
    let m = abs v.hi +^ abs v.lo +^ er in
    make v (((a.e +^ (m *^ b.e)) /^ lower) +^ er)

  let product a b = make (Dd.two_prod a b) quantum

  let to_ball a =
    let v = Dd.to_float a.v in
    ball v (a.e +^ round v)

  let log_float x =
    require (x > 0.0 && Float.is_finite x) "DD logarithm domain";
    let v = Dd.log_float x in
    make v (rounding v Bounds.eps_log)

  let to_scaled a k =
    let v = Dd.to_float_scaled a.v k in
    ball v (up (Float.ldexp a.e k) +^ round v)

  let exp a =
    require (abs a.v.hi <= 700.0 && a.e < 0.01) "DD exp certificate domain";
    let v = Dd.exp a.v in
    let rel = Bounds.eps_exp (abs a.v.hi +^ abs a.v.lo) in
    let er = rounding v rel in
    let m = abs v.hi +^ abs v.lo +^ er in
    make v (er +^ (m *^ a.e /^ down (1.0 -. a.e)))

  let expm1 a =
    require (abs a.v.hi <= 700.0 && a.e < 0.01) "DD expm1 certificate domain";
    let v = Dd.expm1 a.v in
    let er = rounding v (up (Bounds.eps_expm1 (Dd.to_float a.v))) in
    let ex = exp { a with e = 0.0 } in
    make v (er +^ ((magnitude ex +^ ex.e) *^ a.e /^ down (1.0 -. a.e)))

  let normal_pdf a =
    require (abs a.v.hi <= 6.0 && a.e < 0.01) "DD normal domain";
    let v = Normal_dd.pdf a.v in
    let rho = (magnitude a *^ a.e) +^ (0.5 *^ a.e *^ a.e) in
    let er = rounding v Bounds.normal_pdf_relative in
    make v (er +^ ((abs v.hi +^ abs v.lo +^ er) *^ rho /^ down (1.0 -. rho)))

  let normal_cdf a =
    require (abs a.v.hi <= 6.0 && a.e < 0.01) "DD normal domain";
    make (Normal_dd.cdf a.v) (Bounds.normal_cdf_absolute +^ (0.4 *^ a.e))
end

let dd_of_ball (a : t) = D.input a.v 0.0 a.e

let root_time time =
  require (time > 0.0) "positive maturity required";
  let hi, lo = Split.sqrt time in
  Exact_dyadic.sqrt (Dd.of_float time) { Dd.hi; lo };
  D.input hi lo (3.125 *. Bounds.u2 *^ (abs hi +^ abs lo))

let quotient (a : D.t) (b : D.t) =
  let hi, lo = Split.quotient_dd a.v.hi a.v.lo b.v.hi b.v.lo in
  Exact_dyadic.binary "split quotient" Q.div
    (Exact_dyadic.times 16 Exact_dyadic.u2)
    a.v b.v { Dd.hi; lo };
  let lower = down (down (abs b.v.hi -. abs b.v.lo) -. b.e) in
  require (lower > 0.0) "split denominator interval contains zero";
  let er = D.rounding { Dd.hi; lo } (16.0 *. Bounds.u2) in
  D.input hi lo (((a.e +^ ((abs hi +^ abs lo +^ er) *^ b.e)) /^ lower) +^ er)

(* For hi in [0,4096], |lo| <= .001, and finite normal prefactors, the
   reduction, 4u exp certificate, correction and two products cost <12u;
   replacing exp(-lo) by 1-lo costs <=lo². One final quantum covers scaling.
   Exponent uncertainty is transported by exp(delta)-1 <=delta/(1-delta). *)
let scaled_exp ?(k = 0) (m : t) hi lo exponent_error =
  require (abs_float (float k) <= 2048.0) "scale exponent domain";
  if
    Float.is_finite hi && hi >= 4096.0 && abs lo +^ exponent_error <= 0.01 *. hi
  then
    (* |m_exact|<2^1025 and k<=2048. Even with a 1% exponent
       perturbation the mathematical result is below half a quantum. *)
    ball (Split.scaled_exp_neg ~k m.v hi lo) quantum
  else (
    require
      (hi >= 0.0 && hi <= 4096.0 && abs lo <= 0.001 && exponent_error < 0.01)
      "scaled exponential domain";
    let rel = (12.0 *. Bounds.u) +^ (abs lo *^ abs lo) in
    let v = Split.scaled_exp_neg ~k m.v hi lo in
    let er = (abs v *^ rel /^ down (1.0 -. rel)) +^ quantum in
    let input_error =
      (abs (Split.scaled_exp_neg ~k m.e hi lo) /^ down (1.0 -. rel)) +^ quantum
    in
    ball v
      (er +^ input_error
      +^ (abs v +^ er +^ input_error)
         *^ exponent_error
         /^ down (1.0 -. exponent_error)))

let exp_neg_product a b =
  let p = a *. b and lo = Float.fma a b (-.(a *. b)) in
  require (abs p <= 700.0 && abs lo <= 0.001) "discount exponent domain";
  if p >= 0.0 then scaled_exp (c 1.0) p lo quantum
  else
    let ex = Elementary.exp (-.p) in
    let eb =
      ball ex
        (Bounds.elementary_exp_relative *^ abs ex
        /^ down (1.0 -. Bounds.elementary_exp_relative))
    in
    let correction = sub (c 1.0) (c lo) in
    let result = mul eb correction in
    ball result.v (result.e +^ (magnitude result *^ abs lo *^ abs lo) +^ quantum)

let mills z =
  require (z.v >= 0.0 && z.v <= 0x1p400) "Mills domain";
  let argument = mul z (constant Normal.inv_sqrt_2) in
  let v = Cody.erfcx_nonnegative argument.v in
  (* The logarithmic derivative is <2 throughout [-.01,infinity),
     including an argument interval that straddles zero. *)
  let lower = down (argument.v -. argument.e) in
  let sensitivity = if lower > 0.0 then Float.min 2.0 (1.0 /^ lower) else 2.0 in
  let rho = sensitivity *^ argument.e in
  require (rho < 0.01) "Mills uncertainty";
  let rel = (Bounds.erfcx_relative +^ rho) /^ down (1.0 -. rho) in
  let e = abs v *^ rel /^ down (1.0 -. Bounds.erfcx_relative) in
  mul (constant 1.2533141373155002512) (ball v e)

let y_prime z =
  require (z.v <= 0.0 && z.v >= -0x1p400) "Y-prime domain";
  let v = Normalised_black.y_prime z.v in
  (* G(a)=int v exp(-av-v²/2)dv: |G'/G| <=sqrt(pi/2)<1.254.
     The ratio decreases with a because its derivative is minus a variance. *)
  let lower = down (-.z.v -. z.e) in
  let sensitivity = if lower > 0.0 then Float.min 2.0 (2.0 /^ lower) else 2.0 in
  let rho = sensitivity *^ z.e in
  require (rho < 0.01) "Y-prime uncertainty";
  let rel = (Bounds.y_prime_relative +^ rho) /^ down (1.0 -. rho) in
  ball v (abs v *^ rel /^ down (1.0 -. Bounds.y_prime_relative))

let gaussian (d : D.t) prefactor =
  let hi, lo = Split.square d.v.hi in
  let el = (0.5 *. lo) +. (d.v.hi *. d.v.lo) in
  (* Exact square residual; omitted low²/2, one cross-product rounding and
     one addition. The DD argument's uncertainty contributes |d|e+e²/2. *)
  let ee =
    round (d.v.hi *. d.v.lo)
    +^ round el
    +^ (0.5 *^ abs d.v.lo *^ abs d.v.lo)
    +^ (D.magnitude d *^ d.e)
    +^ (0.5 *^ d.e *^ d.e)
    +^ quantum
  in
  scaled_exp prefactor (0.5 *. hi) el ee

let bachelier ?(only_price = false) ~side ~s:forward ~k:strike ~t:time ~r:rate
    ~sigma () =
  require (time > 0.0 && sigma > 0.0) "live positive-variance certificate";
  let theta = Side.sign side in
  let dh, dl = Split.two_sum forward (-.strike) in
  let distance = D.input dh dl 0.0 in
  let rt_dd = root_time time in
  let rt_hi = c rt_dd.v.hi and rt_lo = c rt_dd.v.lo in
  let rt = mul rt_hi (add (c 1.0) (div rt_lo rt_hi)) in
  let rt = ball rt.v (rt.e +^ rt_dd.e) in
  let sd = D.mulf rt_dd sigma in
  let discount = exp_neg_product rate time in
  let discount_dd = D.exp (D.neg (D.product rate time)) in
  let signed_distance = D.mulf distance theta in
  let intrinsic =
    if signed_distance.v.hi > 0.0 then D.mul discount_dd signed_distance
    else D.of_float 0.0
  in
  let far_tail = down (abs dh -. abs dl) > 100.0 *^ (D.magnitude sd +^ sd.e) in
  if only_price && far_tail then
    (* D and s are each finite. Even their exact product below 2^2049,
       multiplied by exp(-100²/2), is below a quantum. *)
    let otm = ball 0.0 quantum in
    let price =
      if signed_distance.v.hi > 0.0 then
        D.to_ball (D.add intrinsic (dd_of_ball otm))
      else otm
    in
    [ ("price", price) ]
  else
    let () = require (sd.v.hi > 0.0) "total volatility underflows" in
    let d_dd = quotient distance sd in
    let d = D.to_ball d_dd in
    let () = require (abs d.v <= 0x1p400) "Gaussian argument domain" in
    (* Price uses the high word of s as prefactor. Account explicitly for its
     low word and formation error; the quotient uses both words. *)
    let sd_hi = ball sd.v.hi (abs sd.v.lo +^ sd.e) in
    let absolute_d = if d.v < 0.0 then neg d else d in
    let otm_m =
      mul
        (mul (mul discount sd_hi) (constant 0.39894228040143267794))
        (y_prime (neg absolute_d))
    in
    let otm = gaussian d_dd otm_m in
    let price =
      if signed_distance.v.hi > 0.0 then
        D.to_ball (D.add intrinsic (dd_of_ball otm))
      else otm
    in
    if only_price then [ ("price", price) ]
    else
      let g = gaussian d_dd in
      let base = mul discount (constant 0.39894228040143267794) in
      let d_over_sigma = if dh = 0.0 && dl = 0.0 then c 0.0 else divf d sigma in
      let delta =
        let tail =
          g
            (mul base
               (mills
                  (if theta *. d.v <= 0.0 then mulf d (-.theta)
                   else mulf d theta)))
        in
        mulf (if theta *. d.v <= 0.0 then tail else sub discount tail) theta
      in
      let d2 = D.mul d_dd d_dd in
      let veta_bracket =
        D.to_ball
          (D.sub (D.mulf rt_dd rate)
             (D.div (D.add (D.of_float 1.0) d2) (D.mulf rt_dd 2.0)))
      in
      let color_bracket =
        D.to_ball
          (D.add (D.of_float rate)
             (D.div (D.sub (D.of_float 1.0) d2) (D.of_float (2.0 *. time))))
      in
      require
        (Float.is_finite (2.0 *. time) && time >= Float.min_float)
        "normal doubled maturity required";
      let theta_annual =
        if abs d_dd.v.hi <= 6.0 then
          let first =
            D.mul
              (D.mulf signed_distance rate)
              (D.normal_cdf (D.mulf d_dd theta))
          in
          let second =
            D.mul (D.normal_pdf d_dd)
              (D.sub (D.mulf sd rate)
                 (D.div (D.of_float sigma) (D.mulf rt_dd 2.0)))
          in
          D.to_ball (D.mul discount_dd (D.add first second))
        else sub (mulf price rate) (g (div (mulf base sigma) (mulf rt 2.0)))
      in
      let charm =
        if abs d_dd.v.hi <= 6.0 then
          let bracket =
            D.add
              (D.mulf (D.normal_cdf (D.mulf d_dd theta)) (theta *. rate))
              (D.div
                 (D.mul (D.normal_pdf d_dd) d_dd)
                 (D.of_float (2.0 *. time)))
          in
          mul (mul discount (D.to_ball bracket)) day
        else
          add
            (mul (mulf delta rate) day)
            (g (mul (divf (mul base d) (2.0 *. time)) day))
      in
      [
        ("price", price);
        ("delta", delta);
        ("gamma", g (div base sd_hi));
        ("theta", divf theta_annual 365.0);
        ("vega", g (mul base rt));
        ("rho", mulf price (-.time));
        ("vanna", g (mul (neg base) d_over_sigma));
        ("volga", g (mul (mul (mul base rt) d) d_over_sigma));
        ("charm", charm);
        ("veta", g (mul (mul base veta_bracket) day));
        ("color", g (mul (mul (div base sd_hi) color_bracket) day));
      ]

let check ~got ~reference b =
  require (replay_matches got b) "certificate replay differs from served bits";
  Bounds.within
    ~error:(Bounds.expansion_error [ got; -.reference ])
    ~bound:(b.e +^ round reference)

let sqrt a =
  let lower = down (a.v -. a.e) in
  require (lower > 0.0) "sqrt interval not positive";
  let v = Float.sqrt a.v in
  ball v ((a.e /^ down (Float.sqrt lower)) +^ round v)

let scale a k =
  let v = Float.ldexp a.v k in
  ball v (up (Float.ldexp a.e k) +^ quantum)

let product_ldexp factors k =
  let m, e =
    List.fold_left
      (fun (m, e) a ->
        let fm, fe = Float.frexp a.v in
        let factor = ball fm (up (Float.ldexp a.e (-fe))) in
        let p = mul m factor in
        let pm, pe = Float.frexp p.v in
        (ball pm (up (Float.ldexp p.e (-pe))), e + fe + pe))
      (c 1.0, k)
      factors
  in
  scale m e

module Polynomials = Kernel_polynomials.Make (struct
  type nonrec t = t

  let c = c
  let constant = constant
  let add = add
  let sub = sub
  let mul = mul
  let div = div
  let neg = neg
  let y_prime = y_prime
end)

let rec power_up a n = if n = 0 then 1.0 else a *^ power_up a (n - 1)

let rec power_down a n =
  if n = 0 then 1.0 else Float.max 0.0 (down (a *. power_down a (n - 1)))

let rec factorial n = if n < 2 then 1.0 else float n *^ factorial (n - 1)
let rec odd_factorial n = if n < 2 then 1.0 else float n *^ odd_factorial (n - 2)

let choose n k =
  let result = ref 1 in
  for j = 1 to k do
    result := !result * (n - j + 1) / j
  done;
  float !result

let asymptotic h t =
  let thresholds =
    [|
      12.347;
      12.958;
      13.729;
      14.718;
      16.016;
      17.769;
      20.221;
      23.816;
      29.419;
      38.93;
      57.171;
      99.347;
    |]
  in
  let tau =
    2.0 *. Float.sqrt (Float.sqrt (Float.sqrt (Float.sqrt epsilon_float)))
  in
  let boundary = -.h.v -. t.v +. tau +. 0.5 in
  let first = ref 0 in
  while !first < 12 && thresholds.(!first) <= boundary do
    incr first
  done;
  let n = 16 - !first in
  let e = mul (div t h) (div t h) in
  let r = mul (add h t) (sub h t) in
  let q = mul (div h r) (div h r) in
  let omega = ref (c 0.0) in
  for j = 16 - !first downto 5 do
    omega := mul q (add (Polynomials.coefficients.(j) e) !omega)
  done;
  let a j = Polynomials.coefficients.(j) e in
  let omega =
    add (a 0)
      (mul q
         (add (a 1)
            (mul q (add (a 2) (mul q (add (a 3) (mul q (add (a 4) !omega))))))))
  in
  let result = mul (div t r) omega in
  (* Alternating Taylor remainder of exp(-v²/2) under the positive integral
     e^(-(a-t)v)-e^(-(a+t)v). Its absolute size is at most term n+1.
     The positive coefficient form avoids cancellation for arbitrarily small t. *)
  let a = down (-.h.v -. h.e) and b = t.v +^ t.e in
  require (a > b && b >= 0.0) "asymptotic remainder domain";
  let r = down (down (a -. b) *. down (a +. b)) in
  require (r > 0.0) "asymptotic remainder denominator";
  let q = power_up (a /^ r) 2 and e = power_up (b /^ a) 2 in
  let p = ref 0.0 in
  for j = n + 1 downto 0 do
    p := (!p *^ e) +^ choose ((2 * n) + 3) ((2 * j) + 1)
  done;
  let remainder =
    b /^ r *^ power_up q (n + 1) *^ 2.0 *^ odd_factorial ((2 * n) + 1) *^ !p
  in
  ball result.v (result.e +^ remainder)

let small_t h t =
  let result = Polynomials.small_t_scaled h t in
  let a = Float.max 0.0 (down (-.h.v -. h.e)) and b = t.v +^ t.e in
  require (b >= 0.0 && b *. b < 17.0) "small-t remainder domain";
  (* I_j(a)=int v^j exp(-av-v²/2)dv. I_17/I_15<=16; hence the
     positive sinh-series remainder is at most 2 t^15 I_15/(15!(1-t²/17)). *)
  let moment0 = 128.0 *^ factorial 7 in
  let moment =
    if a = 0.0 then moment0
    else Float.min moment0 (factorial 15 /^ power_down a 16)
  in
  let denominator = down (1307674368000.0 *. down (1.0 -. (b *^ b /^ 17.0))) in
  let remainder = 2.0 *^ power_up b 15 *^ moment /^ denominator in
  ball result.v (result.e +^ remainder)

let elementary_exp a =
  require (abs a.v <= 700.0 && a.e < 0.01) "elementary exp certificate domain";
  let v = Elementary.exp a.v in
  let er =
    abs v *^ Bounds.elementary_exp_relative
    /^ down (1.0 -. Bounds.elementary_exp_relative)
  in
  ball v (er +^ ((abs v +^ er) *^ a.e /^ down (1.0 -. a.e)) +^ quantum)

let erf_small a =
  require (abs a.v <= Cody.thresh && a.e < 0.01) "small erf domain";
  let v = Cody.erf_small a.v in
  let rel = 26.0 *. Bounds.u in
  ball v ((abs v *^ rel /^ down (1.0 -. rel)) +^ (1.129 *^ a.e) +^ quantum)

let erfcx a =
  require (a.v >= 0.0 && a.v <= 128.0 && a.e < 0.01) "erfcx domain";
  let v = Cody.erfcx_nonnegative a.v in
  let rho = 2.0 *^ a.e in
  let er =
    abs v *^ Bounds.erfcx_relative /^ down (1.0 -. Bounds.erfcx_relative)
  in
  ball v (er +^ ((abs v +^ er) *^ rho /^ down (1.0 -. rho)) +^ quantum)

let cody_tail y =
  if y.v >= 28.0 then (
    require (down (y.v -. y.e) >= 27.5) "erfc zero-rounding interval";
    ball 0.0 quantum)
  else
    let hi, lo = Split.square y.v in
    let exponent_error = (2.0 *^ abs y.v *^ y.e) +^ (y.e *^ y.e) +^ quantum in
    scaled_exp (erfcx y) hi lo exponent_error

let erf a =
  let y = if a.v < 0.0 then neg a else a in
  if y.v <= Cody.thresh then erf_small a
  else
    let r = sub (c 1.0) (cody_tail y) in
    if a.v < 0.0 then neg r else r

let erfc a =
  let y = if a.v < 0.0 then neg a else a in
  if y.v <= Cody.thresh then sub (c 1.0) (erf_small a)
  else
    let r = cody_tail y in
    if a.v < 0.0 then sub (c 2.0) r else r

let black_gaussian (h : D.t) (t : D.t) ?(k = 0) prefactor =
  let eh, el = Normalised_black.vega_exponent h.v.hi h.v.lo t.v.hi t.v.lo in
  let mh = D.magnitude h and mt = D.magnitude t in
  let ee =
    (64.0 *. Bounds.u2 *^ ((mh *^ mh) +^ (mt *^ mt)))
    +^ (mh *^ h.e)
    +^ (0.5 *^ h.e *^ h.e)
    +^ (mt *^ t.e)
    +^ (0.5 *^ t.e *^ t.e)
    +^ (16.0 *. quantum)
  in
  scaled_exp ~k prefactor eh el ee

let black_kernel ?(k = 0) m (x : D.t) (sd : D.t) =
  require (x.v.hi <= 0.0 && sd.v.hi > 0.0) "Black kernel domain";
  require
    (x.v.hi = 0.0 || abs x.v.hi > abs x.v.lo +^ x.e)
    "non-ATM kernel moneyness sign unresolved";
  let tau =
    2.0 *. Float.sqrt (Float.sqrt (Float.sqrt (Float.sqrt epsilon_float)))
  in
  let xv = x.v.hi and sv = sd.v.hi in
  let sd_hi = ball sv (abs sd.v.lo +^ sd.e) in
  if xv = 0.0 then (
    require (x.v.lo = 0.0 && x.e < 0.01) "ATM low word";
    let result =
      scale (mul m (erf (mul (mulf (constant Normal.inv_sqrt_2) 0.5) sd_hi))) k
    in
    (* Across either sign of uncertain moneyness, the full normalized
       call/put derivative has magnitude <= exp(|x|/2) < 2 for |x| < .01.
       This also covers a true ITM intrinsic hidden by a rounded ATM x. *)
    ball result.v (result.e +^ up (Float.ldexp (2.0 *^ magnitude m *^ x.e) k)))
  else
    let h = quotient x sd in
    let t = D.input (0.5 *. sv) (0.5 *. sd.v.lo) ((0.5 *^ sd.e) +^ quantum) in
    let a_lower = down (down (-.h.v.hi -. abs h.v.lo) -. h.e) in
    let t_upper = D.magnitude t +^ t.e in
    if a_lower >= 100.0 && down (a_lower -. t_upper) >= 1.0 then (
      (* M(a-t)-M(a+t) <=1/(a-t)<=1. With a>=100 the Gaussian,
         even scaled by |m|<2^1025 and 2^k (k<=2048), is below a quantum. *)
      require (k <= 2048) "tail scale domain";
      ball 0.0 quantum)
    else
      let h_hi = ball h.v.hi (abs h.v.lo +^ h.e)
      and t_hi = ball t.v.hi (abs t.v.lo +^ t.e) in
      let g = black_gaussian h t in
      let region_i =
        xv < sv *. -13.0
        && (sv *. ((0.5 *. sv) -. (tau +. 0.5 -. 13.0))) +. xv < 0.0
      in
      let region_ii = (sv *. (sv -. (2.0 *. tau))) -. (xv /. -13.0) < 0.0 in
      if region_i || region_ii then
        let shape =
          if region_i then asymptotic h_hi t_hi else small_t h_hi t_hi
        in
        g ~k (mul (mul m (constant Normalised_black.inv_sqrt_2pi)) shape)
      else
        let hf = D.to_ball h in
        let half_exp sign =
          let z = mulf (mulf (c xv) sign) 0.5 in
          let correction = add (c 1.0) (mulf (mulf (c x.v.lo) sign) 0.5) in
          let result = mul (elementary_exp z) correction in
          let rho = (0.5 *^ x.e) +^ (abs x.v.lo *^ abs x.v.lo) in
          ball result.v
            (result.e +^ (magnitude result *^ rho /^ down (1.0 -. rho)))
        in
        let q1 = mul (neg (constant Normal.inv_sqrt_2)) (add hf t_hi)
        and q2 = mul (neg (constant Normal.inv_sqrt_2)) (sub hf t_hi) in
        let two_b =
          if q1.v < Cody.thresh then
            if q2.v < Cody.thresh then
              sub
                (mul (half_exp 1.0) (erfc q1))
                (mul (half_exp (-1.0)) (erfc q2))
            else sub (mul (half_exp 1.0) (erfc q1)) (mul (g (c 1.0)) (erfcx q2))
          else if q2.v < Cody.thresh then
            sub (mul (g (c 1.0)) (erfcx q1)) (mul (half_exp (-1.0)) (erfc q2))
          else mul (g (c 1.0)) (sub (erfcx q1) (erfcx q2))
        in
        let result = mulf two_b 0.5 in
        let result = ball (Float.max result.v 0.0) result.e in
        scale (mul m result) k

let black_coordinates model ~s ~k ~t ~r ~q ~shift =
  let get = function Ok a -> a | Error _ -> raise (Unsupported "admission") in
  let coordinates =
    match model with
    | "bsm" ->
        Black.Bsm.coordinates
          (get
             (Black.Bsm.admit
                {
                  spot = s;
                  strike = k;
                  time_to_expiry = t;
                  rate = r;
                  dividend_yield = q;
                }))
    | "black76" ->
        Black.Black76.coordinates
          (get
             (Black.Black76.admit
                { forward = s; strike = k; time_to_expiry = t; rate = r }))
    | "displaced" ->
        Black.Displaced.coordinates
          (get
             (Black.Displaced.admit
                {
                  forward = s;
                  strike = k;
                  displacement = shift;
                  time_to_expiry = t;
                  rate = r;
                }))
    | _ -> raise (Unsupported "Black coordinate model")
  in
  match coordinates with
  | Black.Coordinates.Expiry _ -> raise (Unsupported "live Black certificate")
  | Black.Coordinates.Live coordinates -> coordinates

let log_ratio s k =
  if s = k then D.of_float 0.0
  else
    let q = s /. k in
    if Float.is_finite q && q >= Float.min_float then
      let residual = Float.fma (-.q) k s in
      let rho =
        D.div (D.input residual 0.0 quantum) (D.mulf (D.of_float k) q)
      in
      let result =
        D.add (D.log_float q) (D.sub rho (D.mulf (D.mul rho rho) 0.5))
      in
      (* |rho| <= u/(1-u); log(1+rho)'s omitted tail <= |rho|³/(3(1-|rho|)). *)
      let ar = D.magnitude rho +^ rho.e in
      D.make result.v
        (result.e +^ (ar *^ ar *^ ar /^ down (3.0 *. down (1.0 -. ar))))
    else D.sub (D.log_float s) (D.log_float k)

let black model ~side ~s:spot_input ~k:strike_input ~t:time ~r:rate ~q:yield
    ~sigma ~shift greek =
  require
    (time > 0.0 && sigma > 0.0 && time >= Float.min_float && time < 0x1p1022)
    "live positive-variance Black certificate";
  let coord =
    black_coordinates model ~s:spot_input ~k:strike_input ~t:time ~r:rate
      ~q:yield ~shift
  in
  let q = coord.yield and r = coord.rate and theta = Side.sign side in
  let sh, sl, kh, kl =
    if model = "displaced" then
      let sh, sl = Split.two_sum spot_input shift
      and kh, kl = Split.two_sum strike_input shift in
      (sh, sl, kh, kl)
    else (spot_input, 0.0, strike_input, 0.0)
  in
  let carry = D.sub (D.product r time) (D.product q time) in
  let correction = sub (div (c sl) (c sh)) (div (c kl) (c kh)) in
  let omitted =
    let a = abs sl /^ sh and b = abs kl /^ kh in
    (a *^ a /^ down (2.0 *. down (1.0 -. a)))
    +^ (b *^ b /^ down (2.0 *. down (1.0 -. b)))
  in
  let correction = ball correction.v (correction.e +^ omitted) in
  let x = D.add (D.add (log_ratio sh kh) carry) (dd_of_ball correction) in
  require_replay
    (x.v.hi = coord.x && x.v.lo = coord.x_low)
    "coordinate replay mismatch";
  require
    (x.v.hi = 0.0 || abs x.v.hi > abs x.v.lo +^ x.e)
    "live Black moneyness sign unresolved";
  (* Scaling input words must be exact before these error-free sums apply. *)
  require
    (Float.ldexp coord.spot coord.exponent = sh
    && Float.ldexp coord.strike coord.exponent = kh
    && Float.ldexp coord.spot_low coord.exponent = sl
    && Float.ldexp coord.strike_low coord.exponent = kl)
    "coordinate scaling loses input";
  let leg value low rate =
    mul
      (mul (c value) (exp_neg_product rate time))
      (add (c 1.0) (div (c low) (c value)))
  in
  let asset = leg coord.spot coord.spot_low q
  and cash = leg coord.strike coord.strike_low r in
  require_replay
    (asset.v = coord.asset && cash.v = coord.cash)
    "leg replay mismatch";
  let rt_dd = root_time time in
  let rt = c rt_dd.v.hi in
  let rt_full = mul rt (add (c 1.0) (div (c rt_dd.v.lo) rt)) in
  let rt_full = ball rt_full.v (rt_full.e +^ rt_dd.e) in
  let sd = D.mulf rt_dd sigma in
  if greek = "price" && sd.v.hi < 0x1p-1000 && coord.x <> 0.0 then (
    let lower_x = down (down (abs x.v.hi -. abs x.v.lo) -. x.e) in
    require
      (lower_x > 100.0 *^ (D.magnitude sd +^ sd.e))
      "underflowing variance separation";
    if theta *. coord.x <= 0.0 then ball 0.0 quantum
    else
      let leg value low rate =
        D.mul (D.exp (D.neg (D.product rate time))) (D.input value low 0.0)
      in
      let a = leg coord.spot coord.spot_low q
      and cc = leg coord.strike coord.strike_low r in
      let intrinsic =
        if abs coord.x <= 0.35 && coord.x_terms <= 1.0 then D.mul cc (D.expm1 x)
        else D.sub a cc
      in
      let result = D.to_scaled (D.mulf intrinsic theta) coord.exponent in
      ball result.v (result.e +^ quantum))
  else if greek = "price" && coord.x = 0.0 && sd.v.hi < 0x1p-500 then (
    let m = mul (sqrt asset) (sqrt cash) in
    let rt_hi = ball rt_dd.v.hi (abs rt_dd.v.lo +^ rt_dd.e) in
    let result =
      product_ldexp
        [ m; constant Normalised_black.inv_sqrt_2pi; c sigma; rt_hi ]
        coord.exponent
    in
    require (x.e < 0.01) "tiny-variance ATM uncertainty";
    let x_error = up (Float.ldexp (2.0 *^ magnitude m *^ x.e) coord.exponent) in
    ball result.v (result.e +^ (magnitude result *^ 0x1p-999) +^ x_error))
  else
    let () =
      require (sd.v.hi >= 0x1p-1000) "Black total volatility underflows"
    in
    let h = quotient x sd in
    let half_s =
      D.input (0.5 *. sd.v.hi) (0.5 *. sd.v.lo) ((0.5 *^ sd.e) +^ quantum)
    in
    let eh, el =
      Normalised_black.vega_exponent h.v.hi h.v.lo half_s.v.hi half_s.v.lo
    in
    let magnitude_h = D.magnitude h and magnitude_t = D.magnitude half_s in
    let ee =
      64.0 *. Bounds.u2
      *^ ((magnitude_h *^ magnitude_h) +^ (magnitude_t *^ magnitude_t))
      +^ (magnitude_h *^ h.e)
      +^ (0.5 *^ h.e *^ h.e)
      +^ (magnitude_t *^ half_s.e)
      +^ (0.5 *^ half_s.e *^ half_s.e)
      +^ (16.0 *. quantum)
    in
    let g ?(k = 0) p = scaled_exp ~k p eh el ee in
    let base =
      mul (mul (sqrt asset) (sqrt cash)) (constant 0.39894228040143267794)
    in
    let price () =
      let m = mul (sqrt asset) (sqrt cash) in
      let otm_x = if x.v.hi > 0.0 then D.neg x else x in
      if theta *. coord.x <= 0.0 then black_kernel ~k:coord.exponent m otm_x sd
      else
        let precise value low rate =
          D.mul (D.exp (D.neg (D.product rate time))) (D.input value low 0.0)
        in
        let a = precise coord.spot coord.spot_low q
        and cc = precise coord.strike coord.strike_low r in
        let intrinsic =
          if abs coord.x <= 0.35 && coord.x_terms <= 1.0 then
            D.mul cc (D.expm1 x)
          else D.sub a cc
        in
        D.to_scaled
          (D.add (D.mulf intrinsic theta)
             (dd_of_ball (black_kernel m otm_x sd)))
          coord.exponent
    in
    if greek = "price" then price ()
    else
      let dd_sum (a : D.t) (b : D.t) =
        let hi, lo = Split.two_sum a.v.hi b.v.hi in
        let low1 = lo +. a.v.lo in
        let low2 = low1 +. b.v.lo in
        let v = hi +. low2 in
        ball v (a.e +^ b.e +^ round low1 +^ round low2 +^ round v)
      in
      let d1 = dd_sum h half_s and d2 = dd_sum h (D.neg half_s) in
      let d2_over_sigma = divf d2 sigma in
      let tail_split leg d =
        if theta *. d.v <= 0.0 then (c 0.0, mills (mulf d (-.theta)))
        else (leg, neg (mills (mulf d theta)))
      in
      let a_part, a_mills = tail_split asset d1
      and c_part, c_mills = tail_split cash d2 in
      let spot = ball coord.spot (abs coord.spot_low) in
      let sd_hi = ball sd.v.hi (abs sd.v.lo +^ sd.e) in
      let up v = scale v coord.exponent in
      let dq = exp_neg_product q time in
      let delta () =
        add
          (div (mulf a_part theta) spot)
          (g (div (mul (mulf base theta) a_mills) spot))
      in
      let w_dd () =
        let lead = D.sub (D.mulf carry 2.0) x in
        let tail = D.div (D.of_float sigma) (D.mulf rt_dd 4.0) in
        if lead.v.hi = 0.0 then (
          let sd_lower = down (down (abs sd.v.hi -. abs sd.v.lo) -. sd.e) in
          let denominator = down (sd_lower *. (2.0 *. time)) in
          require (denominator > 0.0) "w denominator";
          D.make tail.v (tail.e +^ (lead.e /^ denominator)))
        else D.add (D.div lead (D.mulf sd (2.0 *. time))) tail
      in
      let d1_dd () =
        let pieces (a : D.t) =
          D.add (D.input a.v.hi 0.0 a.e) (D.of_float a.v.lo)
        in
        D.add (pieces h) (pieces half_s)
      in
      match greek with
      | "price" -> price ()
      | "delta" -> delta ()
      | "gamma" -> g ~k:(-coord.exponent) (div base (mul (mul spot spot) sd_hi))
      | "vega" -> g ~k:coord.exponent (mul base rt_full)
      | "vanna" -> g (mul (div (neg base) spot) d2_over_sigma)
      | "volga" ->
          g ~k:coord.exponent (mul (mul (mul base rt_full) d1) d2_over_sigma)
      | "rho" when not coord.tied ->
          let time_mantissa, time_exponent = Float.frexp time in
          add
            (product_ldexp [ c theta; c time; c_part ] coord.exponent)
            (g
               ~k:(coord.exponent + time_exponent)
               (mul (mulf (mulf base theta) time_mantissa) c_mills))
      | "rho" -> mulf (price ()) (-.time)
      | "charm" ->
          let d1_dd = d1_dd () and w_dd = w_dd () in
          if abs d1_dd.v.hi <= 6.0 then
            let bracket =
              D.sub
                (D.mulf (D.normal_cdf (D.mulf d1_dd theta)) (theta *. q))
                (D.mul (D.normal_pdf d1_dd) w_dd)
            in
            mul (mul dq (D.to_ball bracket)) day
          else
            sub
              (mul (mulf (delta ()) q) day)
              (g (mul (mul (div base spot) (D.to_ball w_dd)) day))
      | "veta" | "color" ->
          let common = D.add (D.of_float q) (D.mul (d1_dd ()) (w_dd ())) in
          if greek = "veta" then
            let bracket =
              D.to_ball
                (D.sub (D.mul common rt_dd) (D.div (D.of_float 0.5) rt_dd))
            in
            g ~k:coord.exponent (mul (mul base bracket) day)
          else
            let bracket =
              D.to_ball
                (D.add common (D.div (D.of_float 0.5) (D.of_float time)))
            in
            g ~k:(-coord.exponent)
              (mul (mul (div base (mul (mul spot spot) sd_hi)) bracket) day)
      | "theta" ->
          let d1 = d1_dd () in
          let d2 = D.sub d1 sd in
          if abs d1.v.hi <= 6.0 && abs d2.v.hi <= 6.0 then
            let precise value low rate =
              D.mul
                (D.exp (D.neg (D.product rate time)))
                (D.input value low 0.0)
            in
            let a = precise coord.spot coord.spot_low q
            and cc = precise coord.strike coord.strike_low r in
            let leg value rate d =
              D.mul (D.mulf value rate) (D.normal_cdf (D.mulf d theta))
            in
            let carry_terms = D.mulf (D.sub (leg a q d1) (leg cc r d2)) theta in
            let diffusion =
              D.div
                (D.mul (D.mul a (D.normal_pdf d1)) (D.of_float sigma))
                (D.mulf rt_dd 2.0)
            in
            divf
              (D.to_scaled (D.sub carry_terms diffusion) coord.exponent)
              365.0
          else
            let rate_difference = sub (c q) (c r) in
            let ordinary =
              add
                (mulf (price ()) r)
                (up (mul (mulf rate_difference theta) a_part))
            in
            let prefactor =
              sub
                (mul (mul (mulf rate_difference theta) base) a_mills)
                (div (mulf base sigma) (mulf rt_full 2.0))
            in
            divf (add ordinary (g ~k:coord.exponent prefactor)) 365.0
      | _ -> raise (Unsupported "forward rho requires Black price certificate")

let boundary model ~side ~s ~k ~t ~r ~q ~sigma ~shift greek =
  let theta = Side.sign side in
  let q = if model = "bsm" then q else r in
  if t = 0.0 then
    let itm = theta *. (s -. k) > 0.0 in
    match greek with
    | "price" -> ball (Float.max (theta *. (s -. k)) 0.0) (round (s -. k))
    | "delta" -> c (if itm then theta else 0.0)
    | "theta" when itm ->
        divf
          (mulf (D.to_ball (D.sub (D.product q s) (D.product r k))) theta)
          365.0
    | "charm" when itm -> divf (mulf (c q) theta) 365.0
    | _ -> c 0.0
  else (
    require (sigma = 0.0) "boundary certificate requires zero volatility";
    let rt = root_time t in
    if model = "bachelier" then
      let dh, dl = Split.two_sum s (-.k) in
      let distance = D.input (theta *. dh) (theta *. dl) 0.0 in
      let discount = exp_neg_product r t in
      let intrinsic = D.mul (D.exp (D.neg (D.product r t))) distance in
      let price = if distance.v.hi > 0.0 then D.to_ball intrinsic else c 0.0 in
      let delta = if distance.v.hi > 0.0 then mulf discount theta else c 0.0 in
      match greek with
      | "price" -> price
      | "delta" -> delta
      | "theta" -> divf (mulf price r) 365.0
      | "rho" -> mulf price (-.t)
      | "charm" -> divf (mulf delta r) 365.0
      | "vega" when dh = 0.0 && dl = 0.0 ->
          let rtf =
            mul (c rt.v.hi) (add (c 1.0) (div (c rt.v.lo) (c rt.v.hi)))
          in
          let rtf = ball rtf.v (rtf.e +^ rt.e) in
          mul (mul discount rtf) (constant Normalised_black.inv_sqrt_2pi)
      | _ -> c 0.0
    else
      let coord = black_coordinates model ~s ~k ~t ~r ~q ~shift in
      let sh, sl =
        if model = "displaced" then Split.two_sum s shift else (s, 0.0)
      and kh, kl =
        if model = "displaced" then Split.two_sum k shift else (k, 0.0)
      in
      let carry = D.sub (D.product r t) (D.product q t) in
      let low = sub (div (c sl) (c sh)) (div (c kl) (c kh)) in
      let omitted =
        let a = abs sl /^ sh and b = abs kl /^ kh in
        (a *^ a /^ down (2.0 *. down (1.0 -. a)))
        +^ (b *^ b /^ down (2.0 *. down (1.0 -. b)))
      in
      let low = ball low.v (low.e +^ omitted) in
      let x = D.add (D.add (log_ratio sh kh) carry) (dd_of_ball low) in
      let exact_atm = sh = kh && sl = kl && r = q in
      require
        (exact_atm || abs x.v.hi > abs x.v.lo +^ x.e)
        "zero-volatility branch unresolved";
      let itm = theta *. coord.x > 0.0 in
      let leg value low rate =
        mul
          (mul (c value) (exp_neg_product rate t))
          (add (c 1.0) (div (c low) (c value)))
      in
      let asset = leg coord.spot coord.spot_low q
      and cash = leg coord.strike coord.strike_low r in
      let up v = scale v coord.exponent in
      let dq = exp_neg_product q t in
      let price () =
        if not itm then c 0.0
        else
          let precise value low rate =
            D.mul (D.exp (D.neg (D.product rate t))) (D.input value low 0.0)
          in
          let a = precise coord.spot coord.spot_low q
          and cc = precise coord.strike coord.strike_low r in
          let intrinsic =
            if abs coord.x <= 0.35 && coord.x_terms <= 1.0 then
              D.mul cc (D.expm1 x)
            else D.sub a cc
          in
          D.to_scaled (D.mulf intrinsic theta) coord.exponent
      in
      match greek with
      | "price" -> price ()
      | "delta" -> if itm then mulf dq theta else c 0.0
      | "theta" ->
          divf
            (up
               (if itm then mulf (sub (mulf asset q) (mulf cash r)) theta
                else c 0.0))
            365.0
      | "rho" ->
          if coord.tied then mulf (price ()) (-.t)
          else if itm then product_ldexp [ c theta; cash; c t ] coord.exponent
          else c 0.0
      | "charm" -> divf (if itm then mul (mulf (c q) theta) dq else c 0.0) 365.0
      | "vega" when coord.x = 0.0 ->
          up
            (mul
               (mul asset (ball rt.v.hi (abs rt.v.lo +^ rt.e)))
               (constant Normalised_black.inv_sqrt_2pi))
      | _ -> c 0.0)
