(* Property-based tests over random contracts (QCheck, fixed seed).

   Each property holds for the model's real-valued definition and must hold
   for the served binary64 values, up to the stated rounding allowance:

   - bounds: max(intrinsic, 0) <= price <= maximum (A for a call, C for a
     put; Bachelier has no maximum);
   - put-call parity: call - put = A - C;
   - monotone in volatility: σ1 < σ2 implies price(σ1) <= price(σ2);
   - Greeks' signs: 0 <= call delta <= e^(-qT), -e^(-qT) <= put delta <= 0,
     gamma >= 0, vega >= 0;
   - exact homogeneity: price(2^j S, 2^j K) = 2^j price(S, K), bit for bit
     (the library scales by powers of two internally, so this is exact
     outside the subnormals);
   - displaced Black is Black-76 on the sums, bit for bit, wherever the
     sums are representable (dyadic inputs);
   - implied volatility round trips compose forward and inverse error;
   - delta, vega and theta match a Richardson-extrapolated central
     difference of the served price (off the deep tails). *)

open Morphiq_risk

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)
let lognormal s = get (Vol.lognormal s)
let eps = epsilon_float

type contract = {
  call : bool;
  s : float;
  k : float;
  t : float;
  r : float;
  q : float;
  sigma : float;
}

let side c = if c.call then Side.Call else Side.Put

let show c =
  Printf.sprintf "%s S=%h K=%h T=%h r=%h q=%h σ=%h"
    (if c.call then "call" else "put")
    c.s c.k c.t c.r c.q c.sigma

let log_uniform lo hi =
  QCheck.Gen.map
    (fun u -> Float.exp ((u *. Float.log hi) +. ((1.0 -. u) *. Float.log lo)))
    (QCheck.Gen.float_range 0.0 1.0)

let contract_gen =
  let open QCheck.Gen in
  let* call = bool in
  let* s = log_uniform 1e-3 1e3 in
  let* z = float_range (-2.5) 2.5 in
  let* t = log_uniform 1e-3 10.0 in
  let* r = float_range (-0.02) 0.08 in
  let* q = float_range (-0.02) 0.08 in
  let* sigma = log_uniform 1e-3 2.0 in
  return
    { call; s; k = s *. Float.exp (z *. sigma *. Float.sqrt t); t; r; q; sigma }

let arb = QCheck.make ~print:show contract_gen

let bsm c =
  get
    (Black.Bsm.admit
       {
         spot = c.s;
         strike = c.k;
         time_to_expiry = c.t;
         rate = c.r;
         dividend_yield = c.q;
       })

let price c = Black.Bsm.price (bsm c) (side c) (lognormal c.sigma)
let legs c = (c.s *. Float.exp (-.c.q *. c.t), c.k *. Float.exp (-.c.r *. c.t))
let count = 3000

let bounds =
  QCheck.Test.make ~count ~name:"max(intrinsic, 0) <= price <= maximum" arb
    (fun c ->
      let a, cc = legs c in
      let p = price c in
      let intrinsic = if c.call then a -. cc else cc -. a
      and maximum = if c.call then a else cc in
      let slack = 8.0 *. eps *. Float.max a cc in
      p >= Float.max intrinsic 0.0 -. slack && p <= maximum +. slack)

let parity =
  QCheck.Test.make ~count ~name:"call - put = A - C" arb (fun c ->
      let a, cc = legs c in
      let call = price { c with call = true }
      and put = price { c with call = false } in
      Float.abs (call -. put -. (a -. cc)) <= 8.0 *. eps *. Float.max a cc)

let monotone =
  QCheck.Test.make ~count ~name:"price is nondecreasing in σ"
    (QCheck.pair arb (QCheck.float_range 1.0 3.0))
    (fun (c, f) ->
      let p1 = price c and p2 = price { c with sigma = c.sigma *. f } in
      p1 <= (p2 *. (1.0 +. (4.0 *. eps))) +. Float.min_float)

let greek_signs =
  QCheck.Test.make ~count ~name:"delta within its bounds; gamma, vega >= 0" arb
    (fun c ->
      let g = Black.Bsm.greeks (bsm c) (side c) (lognormal c.sigma) in
      let v r = match r with Ok x -> x | Error _ -> Float.nan in
      let dq = Float.exp (-.c.q *. c.t) *. (1.0 +. (4.0 *. eps)) in
      let delta = v g.delta and gamma = v g.gamma in
      let vega =
        v (Result.map (fun x -> (x : _ Units.per_volatility :> float)) g.vega)
      in
      (if c.call then delta >= 0.0 && delta <= dq
       else delta <= 0.0 && delta >= -.dq)
      && gamma >= 0.0 && vega >= 0.0)

let homogeneity =
  QCheck.Test.make ~count
    ~name:"price(2^j S, 2^j K) = 2^j price(S, K), bit for bit"
    (QCheck.pair arb (QCheck.int_range (-300) 300))
    (fun (c, j) ->
      let p = price c
      and pj = price { c with s = Float.ldexp c.s j; k = Float.ldexp c.k j } in
      let scaled = Float.ldexp p j in
      (* Exact unless either value is subnormal, where ldexp itself rounds. *)
      Float.abs scaled < Float.min_float
      || Float.abs p < Float.min_float
      || Int64.equal (Int64.bits_of_float pj) (Int64.bits_of_float scaled))

let dyadic =
  QCheck.Gen.map (fun n -> float n /. 1024.0) (QCheck.Gen.int_range (-200) 2000)

let translation =
  QCheck.Test.make ~count
    ~name:"displaced = Black-76 on representable sums, bit for bit"
    (QCheck.make
       (QCheck.Gen.quad dyadic dyadic
          (QCheck.Gen.map
             (fun n -> float n /. 1024.0)
             (QCheck.Gen.int_range 1 500))
          contract_gen))
    (fun (f, k, d, c) ->
      QCheck.assume (f +. d > 0.0 && k +. d > 0.0);
      let dsp =
        get
          (Black.Displaced.admit
             {
               forward = f;
               strike = k;
               displacement = d;
               time_to_expiry = c.t;
               rate = c.r;
             })
      in
      let b76 =
        get
          (Black.Black76.admit
             {
               forward = f +. d;
               strike = k +. d;
               time_to_expiry = c.t;
               rate = c.r;
             })
      in
      let v = lognormal c.sigma in
      let p1 = Black.Displaced.price dsp (side c) v
      and p2 = Black.Black76.price b76 (side c) v in
      Int64.equal (Int64.bits_of_float p1) (Int64.bits_of_float p2)
      && Black.Displaced.greeks dsp (side c) v
         = Black.Black76.greeks b76 (side c) v)

(* The generating sigma and the exact root of the rounded served quote need
   not agree. Compose forward price error with the inverse error instead of
   accepting a root merely because its served price rounds to the quote. *)
let round_trip =
  QCheck.Test.make ~count
    ~name:"IV round trip composes forward and inverse error" arb (fun c ->
      let a = bsm c in
      let p = price c in
      let spacing = Bounds.ulp (p +. (33.0 *. Bounds.ulp p)) in
      let uncertainty = 32.5 *. spacing in
      let intrinsic = Black.Bsm.price a (side c) (lognormal 0.0) in
      let asset, cash = legs c in
      let maximum = if c.call then asset else cash in
      (* A forward error interval touching a boundary cannot identify the
         generating sigma. Outcome and boundary-root tests cover those rows. *)
      QCheck.assume (p -. uncertainty > intrinsic && p +. uncertainty < maximum);
      match Black.Bsm.implied a (side c) p with
      | Ok (Iv.Root v) ->
          let candidate = Vol.to_float v in
          let x = Float.log (c.s /. c.k) +. ((c.r -. c.q) *. c.t) in
          let rt = Float.sqrt c.t in
          let vega sigma =
            let total = sigma *. rt in
            let d1 = (x /. total) +. (0.5 *. total) in
            c.s
            *. Float.exp (-.c.q *. c.t)
            *. rt
            *. Float.exp (-0.5 *. d1 *. d1)
            /. Float.sqrt (2.0 *. Float.pi)
          in
          (* Black vega has one maximum as sigma varies, hence its minimum
             on an interval is at an endpoint. *)
          let vmin = Float.min (vega candidate) (vega c.sigma) in
          let spacing = Bounds.ulp (p +. (33.0 *. Bounds.ulp p)) in
          let forward = 32.5 *. spacing /. vmin in
          let inverse =
            Iv_bounds.black_root_bound "bsm" ~side_call:c.call ~s:c.s ~k:c.k
              ~t:c.t ~r:c.r ~q:c.q ~shift:0.0 ~quote:p ~root:c.sigma
            *. c.sigma
          in
          Bounds.within
            ~error:(Float.abs (candidate -. c.sigma))
            ~bound:(forward +. inverse)
      | _ -> p = 0.0)

let derivative g h =
  let d h = (g h -. g (-.h)) /. (2.0 *. h) in
  ((4.0 *. d (h /. 2.0)) -. d h) /. 3.0

let finite_differences =
  QCheck.Test.make ~count:1000
    ~name:"delta, vega, theta match differences of the price" arb (fun c ->
      let p = price c in
      let width = c.s *. c.sigma *. Float.sqrt c.t in
      QCheck.assume (p >= 1e-3 *. width && c.t > 0.01);
      let g = Black.Bsm.greeks (bsm c) (side c) (lognormal c.sigma) in
      let v r = match r with Ok x -> x | Error _ -> Float.nan in
      let close got want h =
        Float.abs (got -. want)
        <= (1e-7 *. Float.abs want) +. (256.0 *. eps *. p /. h)
      in
      let hs = 0.01 *. width and hv = 0.01 *. c.sigma and ht = 1e-3 *. c.t in
      close (v g.delta)
        (derivative (fun h -> price { c with s = c.s +. h }) hs)
        hs
      && close
           (v
              (Result.map
                 (fun x -> (x : _ Units.per_volatility :> float))
                 g.vega))
           (derivative (fun h -> price { c with sigma = c.sigma +. h }) hv)
           hv
      && close
           (v
              (Result.map
                 (fun x ->
                   (x : Units.per_calendar_day Units.time_rate :> float))
                 g.theta))
           (-.derivative (fun h -> price { c with t = c.t +. h }) ht /. 365.0)
           (ht *. 365.0))

let () =
  let rand = Random.State.make [| 20261006 |] in
  let code =
    QCheck_base_runner.run_tests ~rand ~verbose:true
      [
        bounds;
        parity;
        monotone;
        greek_signs;
        homogeneity;
        translation;
        round_trip;
        finite_differences;
      ]
  in
  exit code
