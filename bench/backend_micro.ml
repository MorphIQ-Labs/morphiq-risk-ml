open Morphiq_risk
module K = Internal.American_policy
module R = Internal.American_residual

external clock : unit -> float = "morphiq_bench_monotonic"

type matrix = {
  id : int;
  n : int;
  bands : float array array;
  state : K.t;
  residual : R.t;
}

let read path =
  let input = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in input)
    (fun () ->
      let rec loop id acc =
        match input_line input with
        | exception End_of_file -> List.rev acc
        | line ->
            let header = String.split_on_char '\t' line in
            let n =
              match header with
              | [ "MATRIX"; n; _; _ ] -> int_of_string n
              | _ -> failwith "matrix header"
            in
            if n < 2 || n > 8190 then invalid_arg "matrix dimension";
            let bands = Array.init 9 (fun _ -> Array.make (n + 2) 0.) in
            for i = 1 to n do
              match String.split_on_char '\t' (input_line input) with
              | [ "DATA"; lo; d; hi; b; _; _ ] ->
                  bands.(0).(i) <- float_of_string lo;
                  bands.(1).(i) <- float_of_string d;
                  bands.(2).(i) <- float_of_string hi;
                  bands.(3).(i) <- float_of_string b
              | _ -> failwith "matrix row"
            done;
            let state =
              K.create ~lo:bands.(0) ~diag:bands.(1) ~hi:bands.(2)
                ~rhs:bands.(3) ~values:bands.(4) ~payoff:bands.(5)
                ~pivots:bands.(6) ~solution_rhs:bands.(7) ~candidate:bands.(8)
                ~mask:(Array.make (n + 2) false)
                ~oldmask:(Array.make (n + 2) false)
            in
            let residual =
              R.create ~lo:bands.(0) ~diag:bands.(1) ~hi:bands.(2)
                ~rhs:bands.(3) ~values:bands.(8) ~payoff:bands.(5)
            in
            loop (id + 1) ({ id; n; bands; state; residual } :: acc)
      in
      loop 0 [])

let prepare m =
  Array.blit m.bands.(1) 0 m.bands.(6) 0 (m.n + 2);
  Array.blit m.bands.(3) 0 m.bands.(7) 0 (m.n + 2);
  K.reset m.state ~obstacle:false

let solve m =
  let i = ref 2 in
  while !i <= m.n do
    let last = min m.n (!i + 255) in
    if K.run m.state K.Eliminate ~first:!i ~last <> 0 then
      failwith "elimination failure";
    i := last + 1
  done;
  i := m.n;
  while !i >= 1 do
    let last = max 1 (!i - 255) in
    if K.run m.state K.Substitute ~first:!i ~last <> 0 then
      failwith "substitution failure";
    i := last - 1
  done

let residual m =
  R.reset m.residual ~obstacle:false;
  let i = ref 1 in
  while !i <= m.n do
    let last = min m.n (!i + 255) in
    if R.run m.residual ~first:!i ~last <> 0 then failwith "residual failure";
    i := last + 1
  done;
  R.worst m.residual

let main () =
  let input = ref "" and repeats = ref 32 and reverse = ref false in
  Arg.parse
    [
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected positional argument")),
        "end options" );
      ("--input", Arg.Set_string input, "captured matrices");
      ("--repeats", Arg.Set_int repeats, "repetitions");
      ("--reverse", Arg.Set reverse, "reverse sizes and batches");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "american-backend-micro 1";
            exit 0),
        "version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Actual policy microbenchmark";
  if !input = "" || !repeats < 1 then invalid_arg "input/repeats";
  let matrices = read !input in
  if matrices = [] then failwith "empty matrices";
  List.iter
    (fun m ->
      prepare m;
      solve m;
      let r = residual m in
      Printf.printf "SOLUTION\t%d\t%d\t%h" m.id m.n r;
      for i = 1 to m.n do
        Printf.printf "\t%h" m.bands.(8).(i)
      done;
      print_newline ())
    matrices;
  let sizes = List.sort_uniq compare (List.map (fun m -> m.n) matrices) in
  let sizes = if !reverse then List.rev sizes else sizes in
  List.iter
    (fun n ->
      let group = Array.of_list (List.filter (fun m -> m.n = n) matrices) in
      List.iter
        (fun batch ->
          let run full () =
            for k = 0 to !repeats - 1 do
              for j = 0 to batch - 1 do
                let m = group.(((k * batch) + j) mod Array.length group) in
                prepare m;
                if full then (
                  solve m;
                  ignore (Sys.opaque_identity (residual m)))
              done
            done
          in
          run true ();
          Gc.full_major ();
          let start = clock () in
          run false ();
          let preparation = clock () -. start in
          Gc.full_major ();
          let start = clock () in
          run true ();
          let total = clock () -. start in
          Printf.printf "MICRO\t%d\t%d\t%d\t%.17g\t%.17g\n%!" n batch !repeats
            (preparation /. float !repeats)
            (total /. float !repeats))
        (if !reverse then [ 64; 8; 1 ] else [ 1; 8; 64 ]))
    sizes;
  Printf.printf "COMPLETE\t%d\n%!" (List.length matrices)

let () =
  try main ()
  with e ->
    prerr_endline (Printexc.to_string e);
    exit 2
