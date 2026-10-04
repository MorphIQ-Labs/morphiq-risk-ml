open Morphiq_risk
module P = Production

external monotonic : unit -> float = "morphiq_bench_monotonic"

let get = function Ok x -> x | Error _ -> failwith "benchmark admission"

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let sample key n f =
  for _ = 1 to 5 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for round = 1 to 5 do
    Gc.full_major ();
    let gc_before = Gc.quick_stat () in
    let a = words () in
    let cpu = Sys.time () in
    let start = monotonic () in
    for _ = 1 to n do
      ignore (Sys.opaque_identity (f ()))
    done;
    let elapsed = monotonic () -. start in
    let cpu = Sys.time () -. cpu and allocation = 8. *. (words () -. a) in
    let gc_after = Gc.quick_stat () in
    Printf.printf "TIME %s %d %.3f %.3f %.3f %d %d\n%!" key round
      (elapsed *. 1e9 /. float n)
      (cpu *. 1e9 /. float n)
      (allocation /. float n)
      (gc_after.minor_collections - gc_before.minor_collections)
      (gc_after.major_collections - gc_before.major_collections)
  done

let outcome = function
  | Ok (c : float P.certified) ->
      Printf.sprintf "served:%h:%h" c.value c.absolute_error
  | Error (P.Invalid_input _) -> "invalid-input"
  | Error P.Invalid_accuracy -> "invalid-accuracy"
  | Error (P.Unsupported _) -> "unsupported"
  | Error P.Numerical_failure -> "numerical-failure"
  | Error P.Accuracy_exceeded -> "accuracy-exceeded"

let run name admit evaluate =
  let a = get (admit ()) in
  let f () = evaluate a in
  let all () = evaluate (get (admit ())) in
  let expected = outcome (f ()) in
  if outcome (all ()) <> expected then failwith "end-to-end mismatch";
  Printf.printf "CHECK %s %s\n%!" name expected;
  sample (name ^ "/admission") 1000 admit;
  sample (name ^ "/price") 40 f;
  sample (name ^ "/end-to-end") 40 all

let () =
  Arg.parse
    [
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "certified-scalar-v2";
            exit 0),
        "Print benchmark version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Certified scalar price phase benchmark";
  let sigma = get (Vol.lognormal 0.2) in
  List.iter
    (fun (name, strike, time_to_expiry, limit) ->
      let inputs =
        Black.Bsm_carry.
          {
            spot = 100.;
            strike;
            time_to_expiry;
            rate = 0.02;
            dividend_yield = 0.01;
          }
      in
      run ("bsm-" ^ name)
        (fun () -> P.Bsm.admit inputs)
        (fun a -> P.Bsm.evaluate a Side.Call sigma P.Price ~max_error:limit))
    [
      ("ordinary", 95., 1., 1e-9);
      ("tail", 300., 1., 1e-9);
      ("short", 100., 1e-8, 1e-9);
      ("expiry", 95., 0., 1e-9);
      ("accuracy-failure", 95., 1., 0.);
    ];
  run "black76"
    (fun () ->
      P.Black76.admit
        { forward = 100.; strike = 95.; time_to_expiry = 1.; rate = 0.02 })
    (fun a -> P.Black76.evaluate a Side.Put sigma P.Price ~max_error:1e-9);
  run "displaced"
    (fun () ->
      P.Displaced.admit
        {
          forward = -2.;
          strike = -1.;
          displacement = 5.;
          time_to_expiry = 1.;
          rate = 0.02;
        })
    (fun a -> P.Displaced.evaluate a Side.Call sigma P.Price ~max_error:1e-9);
  let normal = get (Vol.normal 2.) in
  run "normal"
    (fun () ->
      P.Bachelier.admit
        { forward = -2.; strike = -1.; time_to_expiry = 1.; rate = 0.02 })
    (fun a -> P.Bachelier.evaluate a Side.Put normal P.Price ~max_error:1e-9)
