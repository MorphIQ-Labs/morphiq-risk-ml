open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "benchmark admission"

let measure label n f =
  for _ = 1 to 20 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for sample = 1 to 5 do
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    let start = Unix.gettimeofday () in
    for _ = 1 to n do
      ignore (Sys.opaque_identity (f ()))
    done;
    let elapsed = Unix.gettimeofday () -. start in
    let allocated = Gc.allocated_bytes () -. before in
    Printf.printf "%s %d %.6f %.3f\n%!" label sample
      (elapsed *. 1e9 /. float n)
      (allocated /. float n)
  done

let () =
  let v = get (Vol.lognormal 0.2) in
  List.iter
    (fun (label, s1, s2, q1, q2, rho) ->
      let receive =
        Exchange.{ spot = s1; dividend_yield = q1; volatility = v }
      in
      let deliver =
        Exchange.{ spot = s2; dividend_yield = q2; volatility = v }
      in
      let correlation = get (Exchange.correlation rho) in
      let admit () =
        Exchange.admit ~receive ~deliver ~time_to_expiry:1. ~correlation
      in
      let a = get (admit ()) in
      measure (label ^ "/admission") 20000 admit;
      measure (label ^ "/evaluation") 200 (fun () ->
          Exchange.price a ~max_error:1e-9);
      measure (label ^ "/end-to-end") 200 (fun () ->
          Exchange.price (get (admit ())) ~max_error:1e-9))
    [
      ("ordinary", 100., 95., 0.01, 0.02, 0.5);
      ("singular", 100., 100., 0., 0., Float.pred 1.);
      ("tail", 1., 1000., 0., 0., 0.5);
      ("failure", 100., 95., -1000., 0., 0.5);
    ];
  let bsm =
    get
      (Production.Bsm.admit
         {
           spot = 100.;
           strike = 95.;
           time_to_expiry = 1.;
           rate = 0.02;
           dividend_yield = 0.01;
         })
  in
  measure "control/bsm-certified" 200 (fun () ->
      Production.Bsm.evaluate bsm Side.Call v Production.Price ~max_error:1e-9)
