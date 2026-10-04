(* Price, implied volatility and Greeks describe one function.

   Each oracle checks one quantity against an independent reference. These
   checks tie the quantities to each other, which no single-quantity oracle
   does:

   1. Displaced Black is Black-76 on the exact sums: where F + d and K + d are
      representable, price, IV and every Greek equal Black-76's bit for bit.
   2. The implied volatility of a model's own price recovers it: the root σ'
      is within 2 ULP of the generating σ, within 4x the inverse's attainable
      relative accuracy (docs/error-analysis.md §6), or reprices within 2 ULP
      of the quote. The served zero-volatility price always has an
      inverse: σ = 0, or the exact positive root of a quote that rounded the
      intrinsic upward, which reprices to it. This holds because the price
      and the inverse share one zero-variance boundary.
   3. Each first-order Greek is the derivative of the served price: delta,
      vega, theta and rho agree with a Richardson-extrapolated central
      difference of the price, where the price is at least 1e-3 of the
      contract's natural width. The step is 1% of that width
      (F' σ √T for the Black family, σ √T for Bachelier). The tolerance is
      1e-7 relative plus the difference's rounding noise, 256 ε |V| / h. *)

open Morphiq_risk

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)
let lognormal s = get (Vol.lognormal s)
let failures = ref []
let fail fmt = Printf.ksprintf (fun m -> failures := m :: !failures) fmt
let sides = [ Side.Call; Side.Put ]
let side_name = function Side.Call -> "call" | Side.Put -> "put"
let ulps = Float_score.ulps

(* 1. Displaced Black and Black-76 on representable sums. Dyadic values keep
   F + d and K + d exact. *)
let translation () =
  let n = ref 0 in
  List.iter
    (fun (f, k, d) ->
      List.iter
        (fun (t, r, sigma) ->
          List.iter
            (fun side ->
              assert (f +. d -. d = f && k +. d -. k = d);
              let dsp =
                get
                  (Black.Displaced.admit
                     {
                       forward = f;
                       strike = k;
                       displacement = d;
                       time_to_expiry = t;
                       rate = r;
                     })
              in
              let b76 =
                get
                  (Black.Black76.admit
                     {
                       forward = f +. d;
                       strike = k +. d;
                       time_to_expiry = t;
                       rate = r;
                     })
              in
              let v = lognormal sigma in
              let p1 = Black.Displaced.price dsp side v
              and p2 = Black.Black76.price b76 side v in
              incr n;
              if
                (not (Float.is_finite p1 && Float.is_finite p2))
                || Int64.bits_of_float p1 <> Int64.bits_of_float p2
              then
                fail "translation price %s F=%h K=%h d=%h: %h vs %h"
                  (side_name side) f k d p1 p2;
              let g1 = Black.Displaced.greeks dsp side v
              and g2 = Black.Black76.greeks b76 side v in
              if g1 <> g2 then
                fail "translation greeks %s F=%h K=%h d=%h differ"
                  (side_name side) f k d;
              if p1 > 0.0 then
                let i1 = Black.Displaced.implied dsp side p1
                and i2 = Black.Black76.implied b76 side p1 in
                if i1 <> i2 then
                  fail "translation IV %s F=%h K=%h d=%h differ"
                    (side_name side) f k d)
            sides)
        [
          (0.25, 0.03, 0.2);
          (1.0, -0.01, 0.01);
          (5.0, 0.0, 1.5);
          (0.0078125, 0.05, 0.4);
        ])
    [
      (-0.0078125, 0.015625, 0.03125);
      (0.5, 0.25, 0.125);
      (-0.0234375, -0.0078125, 0.03125);
      (3.0, 3.0, 1.0);
    ];
  !n

(* 2 and 3, over a grid shared by the four models. *)
type model = {
  name : string;
  price : Side.t -> float -> float;  (** at volatility σ *)
  implied : Side.t -> float -> float option;  (** Some σ for a root *)
  greeks : Side.t -> float -> float * float * float * float;
      (** delta, vega, theta (per day), rho *)
  bump : [ `Spot | `Time | `Rate ] -> float -> Side.t -> float -> float;
      (** price with a coordinate moved by h *)
  width : float -> float;
      (** the price's natural width in the spot coordinate, at σ *)
  attainable : float -> float;
      (** the inverse's attainable relative accuracy at σ *)
}

let black (type i a)
    (module M : Black.MODEL with type inputs = i and type admitted = a) name
    (inputs : i) (move : [ `Spot | `Time | `Rate ] -> float -> i)
    ~shifted_forward ~time ~log_moneyness =
  let admitted = get (M.admit inputs) in
  let root = function Ok (Iv.Root v) -> Some (Vol.to_float v) | _ -> None in
  let num (g : Vol.lognormal Greeks.t) =
    let f r = match r with Ok v -> v | Error _ -> Float.nan in
    ( f g.delta,
      f (Result.map (fun v -> (v : _ Units.per_volatility :> float)) g.vega),
      f (Result.map (fun v -> (v : _ Units.time_rate :> float)) g.theta),
      f g.rho )
  in
  {
    name;
    price = (fun side s -> M.price admitted side (lognormal s));
    implied = (fun side p -> root (M.implied admitted side p));
    greeks = (fun side s -> num (M.greeks admitted side (lognormal s)));
    bump =
      (fun c h side s -> M.price (get (M.admit (move c h))) side (lognormal s));
    width = (fun s -> shifted_forward *. s *. Float.sqrt time);
    attainable =
      (fun s ->
        let sd = s *. Float.sqrt time and x = -.Float.abs log_moneyness in
        let b = Internal.Normalised_black.b x sd
        and v = Internal.Normalised_black.vega x sd in
        (1.0 +. Float.abs (b /. (sd *. v))) *. epsilon_float);
  }

let models t =
  let f = 1.05 and k = 1.0 and r = 0.03 and q = 0.01 in
  [
    black
      (module Black.Bsm)
      "bsm"
      { spot = f; strike = k; time_to_expiry = t; rate = r; dividend_yield = q }
      (fun c h ->
        match c with
        | `Spot ->
            {
              spot = f +. h;
              strike = k;
              time_to_expiry = t;
              rate = r;
              dividend_yield = q;
            }
        | `Time ->
            {
              spot = f;
              strike = k;
              time_to_expiry = t +. h;
              rate = r;
              dividend_yield = q;
            }
        | `Rate ->
            {
              spot = f;
              strike = k;
              time_to_expiry = t;
              rate = r +. h;
              dividend_yield = q;
            })
      ~shifted_forward:f ~time:t
      ~log_moneyness:(Float.log (f /. k) +. ((r -. q) *. t));
    black
      (module Black.Black76)
      "black76"
      { forward = f; strike = k; time_to_expiry = t; rate = r }
      (fun c h ->
        match c with
        | `Spot ->
            { forward = f +. h; strike = k; time_to_expiry = t; rate = r }
        | `Time ->
            { forward = f; strike = k; time_to_expiry = t +. h; rate = r }
        | `Rate ->
            { forward = f; strike = k; time_to_expiry = t; rate = r +. h })
      ~shifted_forward:f ~time:t
      ~log_moneyness:(Float.log (f /. k));
    black
      (module Black.Displaced)
      "displaced"
      {
        forward = 0.0123;
        strike = 0.0071;
        displacement = 0.03;
        time_to_expiry = t;
        rate = r;
      }
      (fun c h ->
        match c with
        | `Spot ->
            {
              forward = 0.0123 +. h;
              strike = 0.0071;
              displacement = 0.03;
              time_to_expiry = t;
              rate = r;
            }
        | `Time ->
            {
              forward = 0.0123;
              strike = 0.0071;
              displacement = 0.03;
              time_to_expiry = t +. h;
              rate = r;
            }
        | `Rate ->
            {
              forward = 0.0123;
              strike = 0.0071;
              displacement = 0.03;
              time_to_expiry = t;
              rate = r +. h;
            })
      ~shifted_forward:0.0423 ~time:t
      ~log_moneyness:(Float.log (0.0423 /. 0.0371));
    (let inputs c h : Bachelier.inputs =
       match c with
       | `Spot ->
           {
             forward = 0.0123 +. h;
             strike = 0.0071;
             time_to_expiry = t;
             rate = r;
           }
       | `Time ->
           {
             forward = 0.0123;
             strike = 0.0071;
             time_to_expiry = t +. h;
             rate = r;
           }
       | `Rate ->
           {
             forward = 0.0123;
             strike = 0.0071;
             time_to_expiry = t;
             rate = r +. h;
           }
     in
     let a = get (Bachelier.admit (inputs `Spot 0.0)) in
     let normal s = get (Vol.normal s) in
     let f r = match r with Ok v -> v | Error _ -> Float.nan in
     {
       name = "bachelier";
       price = (fun side s -> Bachelier.price a side (normal s));
       implied =
         (fun side p ->
           match Bachelier.implied a side p with
           | Ok (Iv.Root v) -> Some (Vol.to_float v)
           | _ -> None);
       greeks =
         (fun side s ->
           let g = Bachelier.greeks a side (normal s) in
           ( f g.delta,
             f
               (Result.map
                  (fun v -> (v : _ Units.per_volatility :> float))
                  g.vega),
             f (Result.map (fun v -> (v : _ Units.time_rate :> float)) g.theta),
             f g.rho ));
       bump =
         (fun c h side s ->
           Bachelier.price (get (Bachelier.admit (inputs c h))) side (normal s));
       width = (fun s -> s *. Float.sqrt t);
       attainable = (fun _ -> 2.0 *. epsilon_float);
     });
  ]

(* Richardson-extrapolated central difference: (4 D(h/2) - D(h))/3, error O(h^4). *)
let derivative g h =
  let d h = (g h -. g (-.h)) /. (2.0 *. h) in
  ((4.0 *. d (h /. 2.0)) -. d h) /. 3.0

let close name what ~value ~h got want =
  let tolerance =
    (1e-7 *. Float.abs want) +. (256.0 *. epsilon_float *. Float.abs value /. h)
  in
  if not (Bounds.within ~error:(Float.abs (got -. want)) ~bound:tolerance) then
    fail "%s %s: analytic %h, difference %h" name what got want

let self_consistency () =
  let n = ref 0 in
  List.iter
    (fun t ->
      List.iter
        (fun m ->
          let sigmas =
            if m.name = "bachelier" then [ 0.0; 0.001; 0.005; 0.02 ]
            else [ 0.0; 0.05; 0.2; 0.8 ]
          in
          List.iter
            (fun side ->
              List.iter
                (fun sigma ->
                  incr n;
                  let p = m.price side sigma in
                  (match m.implied side p with
                  | Some s'
                    when not
                           (Float.is_finite s' && Float.is_finite p
                           && Float.is_finite (m.price side s')) ->
                      fail "%s IV consistency received nonfinite values" m.name
                  | Some s' when sigma = 0.0 ->
                      let u = ulps (m.price side s') p in
                      if s' <> 0.0 && u > 2.0 then
                        fail
                          "%s IV of the zero-vol price %h is %h, which \
                           reprices %.0f ulp away"
                          m.name p s' u
                  | Some s' ->
                      let u = ulps (m.price side s') p and us = ulps s' sigma in
                      (* Within 4x the inverse's attainable relative accuracy
                         (docs/error-analysis.md §6), or repricing the quote. *)
                      let attainable = 4.0 *. m.attainable sigma in
                      if
                        not
                          (u <= 2.0 || us <= 2.0
                          || Bounds.within
                               ~error:(Float.abs (s' -. sigma))
                               ~bound:(attainable *. sigma))
                      then
                        fail
                          "%s %s T=%g σ=%g: IV %h is %.0f ulp from σ and \
                           reprices %.0f ulp from the quote"
                          m.name (side_name side) t sigma s' us u
                  | None ->
                      fail "%s %s T=%g σ=%g: no root for its own price %h"
                        m.name (side_name side) t sigma p);
                  (* Derivative checks apply off the deep tails, where a finite
                     difference's truncation error is below 1e-7; the tails are
                     covered by the oracles. *)
                  if sigma > 0.0 && p >= 1e-3 *. m.width sigma then (
                    let delta, vega, theta, rho = m.greeks side sigma in
                    let value = p in
                    let hs = 0.01 *. m.width sigma
                    and hv = 0.01 *. sigma
                    and ht = 1e-3 *. t
                    and hr = 1e-4 in
                    close m.name "delta" ~value ~h:hs delta
                      (derivative (fun h -> m.bump `Spot h side sigma) hs);
                    close m.name "vega" ~value ~h:hv vega
                      (derivative (fun h -> m.price side (sigma +. h)) hv);
                    (* theta = -dV/dT per calendar day *)
                    close m.name "theta" ~value ~h:(ht *. 365.0) theta
                      (-.derivative (fun h -> m.bump `Time h side sigma) ht
                      /. 365.0);
                    (* the rate moves with the model's other inputs fixed, so a forward model's
                       rho is -T V, as served *)
                    close m.name "rho" ~value ~h:hr rho
                      (derivative (fun h -> m.bump `Rate h side sigma) hr)))
                sigmas)
            sides)
        (models t))
    [ 1.0 /. 12.0; 1.0; 7.0 ];
  !n

let () =
  let a = translation () in
  let b = self_consistency () in
  Printf.printf "translation cases %d, self-consistency cases %d, failures %d\n"
    a b (List.length !failures);
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
