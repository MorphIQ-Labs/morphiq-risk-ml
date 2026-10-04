open Morphiq_risk
module M = Internal.Model_enclosure
module P = Production

let ok = function Ok x -> x | Error _ -> failwith "benchmark admission"

let sample name n f =
  for _ = 1 to 5 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for round = 1 to 5 do
    Gc.full_major ();
    let allocation = Gc.allocated_bytes () and start = Unix.gettimeofday () in
    for _ = 1 to n do
      ignore (Sys.opaque_identity (f ()))
    done;
    let seconds = Unix.gettimeofday () -. start in
    let bytes = Gc.allocated_bytes () -. allocation in
    Printf.printf "%s %d %.3f %.3f\n%!" name round
      (seconds *. 1e9 /. float n)
      (bytes /. float n)
  done

let () =
  let volatility = ok (Vol.lognormal 0.2) in
  let inputs =
    Black.Bsm_carry.
      {
        spot = 100.;
        strike = 95.;
        time_to_expiry = 1.;
        rate = 0.02;
        dividend_yield = 0.01;
      }
  in
  let admitted = ok (P.Bsm.admit inputs) in
  let prepare () =
    M.black ~spot:100. ~spot_low:0. ~strike:95. ~strike_low:0. ~time:1.
      ~rate:0.02 ~yield:0.01
  in
  let model = prepare () in
  let sensitivities =
    M.[ Delta; Gamma; Theta; Vega; Rho; Vanna; Volga; Charm; Veta; Color ]
  in
  sample "model-preparation" 100 prepare;
  sample "prepared-model-eleven-enclosures" 20 (fun () ->
      let price = M.price model Side.Call 0.2 in
      price
      :: List.map (M.greek model Side.Call 0.2 ~rho_forward:false) sensitivities);
  sample "production-price" 100 (fun () ->
      P.Bsm.evaluate admitted Side.Call volatility P.Price ~max_error:1e-9)
