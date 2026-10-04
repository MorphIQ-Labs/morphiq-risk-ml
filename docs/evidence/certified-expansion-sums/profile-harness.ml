open Morphiq_risk
let ok = function Ok x -> x | Error _ -> failwith "request failed"
let sample label n f =
  for _ = 1 to 20 do ignore (Sys.opaque_identity (f ())) done;
  for r = 1 to 1 do
    Gc.full_major ();
    let a = Gc.allocated_bytes () in
    let start = Unix.gettimeofday () in
    for _ = 1 to n do ignore (Sys.opaque_identity (f ())) done;
    let dt = Unix.gettimeofday () -. start in
    let bytes = Gc.allocated_bytes () -. a in
    Printf.printf "%s %d %.3f ns/call %.1f bytes/call\n%!" label r (dt *. 1e9 /. float n) (bytes /. float n)
  done
let () =
 let inputs = Black.Bsm_carry.{spot=100.;strike=95.;time_to_expiry=1.;rate=0.02;dividend_yield=0.01} in
 let v = ok (Vol.lognormal 0.2) in
 let a = ok (Black.Bsm.admit inputs) in
 let p = ok (Production.Bsm.admit inputs) in
 Printf.printf "fast value %.17g certified value %.17g\n%!" (Black.Bsm.price a Side.Call v) (ok (Production.Bsm.evaluate p Side.Call v Production.Price ~max_error:1e-9)).value;
 sample "fast-price" 100000 (fun () -> Black.Bsm.price a Side.Call v);
 sample "certified-price" 4000 (fun () -> ok (Production.Bsm.evaluate p Side.Call v Production.Price ~max_error:1e-9));
 sample "fast-admit-and-price" 100000 (fun () -> Black.Bsm.price (ok (Black.Bsm.admit inputs)) Side.Call v);
 sample "certified-admit-and-price" 4000 (fun () -> ok (Production.Bsm.evaluate (ok (Production.Bsm.admit inputs)) Side.Call v Production.Price ~max_error:1e-9))
