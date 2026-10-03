(* Manual DD exponential throughput/allocation evidence. Fixed exact inputs,
   one warm-up and nine batches; pair runs with bench/assurance.exe. *)
open Morphiq_risk.Internal

let count = 20_000
let sink = ref (Dd.of_float 0.0)

let words () =
  let a, p, b = Gc.counters () in
  a +. b -. p

let measure name f xs =
  let run () = Array.iter (fun x -> sink := Sys.opaque_identity (f x)) xs in
  run ();
  let samples =
    Array.init 9 (fun _ ->
        Gc.full_major ();
        let w = words () in
        let start = Unix.gettimeofday () in
        run ();
        let elapsed = Unix.gettimeofday () -. start in
        (elapsed *. 1e9 /. float count, (words () -. w) /. float count))
  in
  Array.sort (fun (a, _) (b, _) -> compare a b) samples;
  Printf.printf "%s,%.3f,%.3f,%.3f,%.3f\n%!" name
    (fst samples.(4))
    (fst samples.(0))
    (fst samples.(8))
    (snd samples.(4))

let () =
  Arg.parse
    [
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline Morphiq_risk.version;
            exit 0),
        "Library version" );
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected positional argument")),
        "End options" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected positional argument"))
    "dd_exponential: fixed-corpus manual benchmark";
  let inputs limit =
    Array.init count (fun i ->
        let x = limit *. ((2.0 *. float i /. float count) -. 1.0) in
        Dd.add_float (Dd.of_float x) (Float.ldexp x (-55)))
  in
  print_endline "function,median_ns,min_ns,max_ns,allocated_words";
  measure "exp_reduced" Dd.exp (inputs 0.347);
  measure "exp_wide" Dd.exp (inputs 700.0);
  measure "expm1_reduced" Dd.expm1 (inputs 0.346);
  measure "expm1_wide" Dd.expm1 (inputs 700.0)
