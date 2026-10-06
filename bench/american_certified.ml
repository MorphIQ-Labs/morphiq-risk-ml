open Morphiq_risk
module A = Early_exercise.Bsm
module C = A.Certified

external monotonic : unit -> float = "morphiq_bench_monotonic"

let get = function Ok x -> x | Error _ -> failwith "benchmark refusal"

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let sample name n f =
  for _ = 1 to 20 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for round = 1 to 5 do
    Gc.full_major ();
    let before = words () and cpu = Sys.time () and start = monotonic () in
    for _ = 1 to n do
      ignore (Sys.opaque_identity (f ()))
    done;
    let elapsed = monotonic () -. start in
    let cpu = Sys.time () -. cpu and allocation = 8. *. (words () -. before) in
    Printf.printf "TIME %s %d %d %.3f %.3f %.3f\n%!" name round n
      (elapsed *. 1e9 /. float n)
      (cpu *. 1e9 /. float n)
      (allocation /. float n)
  done

let run name p side n =
  let max_error = get (C.absolute_error_limit 1e-10) in
  let admitted = get (A.admit p) in
  let price () = get (C.price admitted side ~max_error) in
  let full () = get (C.price (get (A.admit p)) side ~max_error) in
  let value = price () in
  if full () <> value then failwith "end-to-end mismatch";
  Printf.printf "CHECK %s %h %h\n%!" name value.value value.absolute_error;
  sample (name ^ "/admission") 10000 (fun () -> get (A.admit p));
  sample (name ^ "/price") n price;
  sample (name ^ "/end-to-end") n full

let () =
  if Array.length Sys.argv <> 1 then (
    Printf.eprintf "Usage: american_certified (fixed #116 engineering corpus)\n";
    exit 2);
  let p =
    A.
      {
        spot = 100.;
        strike = 100.;
        rate = 0.05;
        dividend_yield = 0.;
        volatility = get (Vol.lognormal 0.2);
        time_to_expiry = 1.;
        opens_at = 0.;
      }
  in
  run "call" p Side.Call 100;
  run "terminal-put"
    { p with dividend_yield = 0.02; opens_at = 1. }
    Side.Put 100;
  run "expiry" { p with time_to_expiry = 0.; spot = 101. } Side.Call 10000
