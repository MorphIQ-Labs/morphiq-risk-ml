open Morphiq_risk
module M = Internal.Model_enclosure
module E = Internal.Enclosure

external monotonic : unit -> float = "morphiq_bench_monotonic"

let sample name f =
  for _ = 1 to 3 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for round = 1 to 5 do
    Gc.full_major ();
    let a, b, c = Gc.counters () in
    let start = monotonic () in
    for _ = 1 to 20 do
      ignore (Sys.opaque_identity (f ()))
    done;
    let ns = (monotonic () -. start) *. 1e9 /. 20. in
    let x, y, z = Gc.counters () in
    Printf.printf "%s %d %.3f %.3f\n%!" name round ns
      (8. *. (x +. z -. y -. a -. c +. b) /. 20.)
  done

let () =
  let black =
    M.black ~spot:100. ~spot_low:0. ~strike:95. ~strike_low:0. ~time:1.
      ~rate:0.02 ~yield:0.01
  and normal = M.normal ~forward:(-2.) ~strike:(-1.) ~time:1. ~rate:0.02 in
  let sensitivities =
    M.[ Delta; Gamma; Theta; Vega; Rho; Vanna; Volga; Charm; Veta; Color ]
  in
  List.iter
    (fun (name, model, sigma) ->
      sample (name ^ "/ten-greeks") (fun () ->
          List.map
            (M.greek model Side.Call sigma ~rho_forward:false)
            sensitivities);
      List.iter
        (fun (q, label) ->
          sample
            (name ^ "/" ^ label)
            (fun () -> M.greek model Side.Call sigma ~rho_forward:false q))
        M.[ (Delta, "delta"); (Vega, "vega"); (Theta, "theta") ])
    [ ("black", black, 0.2); ("normal", normal, 10.) ];
  let spot = E.exact 100. and strike = E.exact 95. and t = E.exact 1. in
  let x =
    E.add
      (E.log (E.div spot strike))
      (E.mul (E.sub (E.exact 0.02) (E.exact 0.01)) t)
  in
  let root_time = E.sqrt t in
  let asset = E.mul spot (E.exp (E.neg (E.mul (E.exact 0.01) t))) in
  let common () =
    let total = E.mul root_time (E.exact 0.2) in
    let h = E.div x total and half = E.scale total (-1) in
    let d1 = E.add h half and d2 = E.sub h half in
    (d1, d2, E.mul asset (M.pdf d1))
  in
  sample "black/common-d1-d2-weighted-density" common;
  let d1, d2, _ = common () in
  sample "black/cdf-d1" (fun () -> M.cdf (E.mul_float d1 1.));
  sample "black/cdf-d2" (fun () -> M.cdf (E.mul_float d2 1.))
