open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "benchmark admission"

let sample label round n f =
  Gc.full_major ();
  let before = Gc.allocated_bytes () and start = Unix.gettimeofday () in
  for _ = 1 to n do
    ignore (Sys.opaque_identity (f ()))
  done;
  let elapsed = Unix.gettimeofday () -. start in
  let allocation = Gc.allocated_bytes () -. before in
  Printf.printf "%s %d %.6f %.3f\n%!" label round
    (elapsed *. 1e9 /. float n)
    (allocation /. float n)

let () =
  let v = get (Vol.lognormal 0.2) in
  List.iter
    (fun (name, s1, s2, q1, q2, rho) ->
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
      let evaluate () = Exchange.price a ~max_error:1e-9 in
      let end_to_end () = Exchange.price (get (admit ())) ~max_error:1e-9 in
      if evaluate () <> end_to_end () then failwith "paired outcomes differ";
      for _ = 1 to 20 do
        ignore (Sys.opaque_identity (evaluate ()));
        ignore (Sys.opaque_identity (end_to_end ()))
      done;
      for round = 1 to 7 do
        sample (name ^ "/admission") round 20000 admit;
        let first, second =
          if round mod 2 = 0 then
            (("evaluation", evaluate), ("end-to-end", end_to_end))
          else (("end-to-end", end_to_end), ("evaluation", evaluate))
        in
        List.iter
          (fun (phase, f) -> sample (name ^ "/" ^ phase) round 100 f)
          [ first; second ]
      done)
    [
      ("ordinary", 100., 95., 0.01, 0.02, 0.5);
      ("singular", 100., 100., 0., 0., Float.pred 1.);
      ("tail", 1., 1000., 0., 0., 0.5);
      ("failure", 100., 95., -1000., 0., 0.5);
    ]
