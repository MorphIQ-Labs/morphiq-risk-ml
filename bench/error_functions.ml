(* Manual fixed-corpus scalar comparison. Same harness in both worktrees. *)
open Morphiq_risk

let count = 20000
let sink = ref 0.0

let words () =
  let a, p, b = Gc.counters () in
  a +. b -. p

let measure name f low high =
  let xs =
    Array.init count (fun i -> low +. ((high -. low) *. float i /. float count))
  in
  let run () = Array.iter (fun x -> sink := Sys.opaque_identity (f x)) xs in
  run ();
  let samples =
    Array.init 9 (fun _ ->
        Gc.full_major ();
        let w = words () and t = Unix.gettimeofday () in
        run ();
        ( (Unix.gettimeofday () -. t) *. 1e9 /. float count,
          (words () -. w) /. float count ))
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
            print_endline version;
            exit 0),
        "Library version" );
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected positional argument")),
        "End options" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected positional argument"))
    "error_functions: fixed-corpus benchmark";
  print_endline "function,median_ns,min_ns,max_ns,allocated_words";
  List.iter
    (fun (name, f, a, b) -> measure name f a b)
    [
      ("erfcx_small", Internal.Cody.erfcx, 0., 0.5);
      ("erfcx_middle", Internal.Cody.erfcx, 0.5, 12.);
      ("erfcx_tail", Internal.Cody.erfcx, 12., 128.);
      ("erfcx_negative", Internal.Cody.erfcx, -26.62, 0.);
      ("erf", Internal.Cody.erf, -8., 8.);
      ("erfc", Internal.Cody.erfc, 0., 28.);
      ("cdf", Normal.norm_cdf, -12., 12.);
    ]
