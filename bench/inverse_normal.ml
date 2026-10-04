(* Manual fixed-corpus scalar comparison. Same harness in both worktrees. *)
open Morphiq_risk

let count = 20000
let sink = ref 0.0

let words () =
  let a, p, b = Gc.counters () in
  a +. b -. p

let measure name f xs =
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
    "inverse_normal: fixed-corpus benchmark";
  print_endline "function,median_ns,min_ns,max_ns,allocated_words";
  let linear a b =
    Array.init count (fun i ->
        a +. ((b -. a) *. (float i +. 0.5) /. float count))
  in
  measure "inverse_central" Normal.norm_inv (linear 0.25 0.75);
  measure "inverse_tail" Normal.norm_inv (linear 0.0001 0.2499);
  measure "inverse_extreme" Normal.norm_inv
    (Array.init count (fun i -> Float.ldexp 1.0 (-1 - (i mod 1074))));
  let inputs =
    Array.init count (fun i ->
        let x = -.(float (i mod 100) /. 10.) in
        let s = 0.1 +. (float (i mod 71) /. 10.) in
        let s = Float.max s (Float.abs x /. 8.0) in
        let beta = Internal.Normalised_black.b x s in
        if not (beta > 0.0 && beta < Internal.Elementary.exp (0.5 *. x)) then
          failwith "LBR benchmark precondition";
        (beta, x))
  in
  measure "lbr_proposal" (fun (beta, x) -> Internal.Lbr.solve beta x) inputs
