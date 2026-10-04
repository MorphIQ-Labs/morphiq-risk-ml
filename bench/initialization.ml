(* Force linking/initialization while avoiding numerical workload in startup timing. *)
let () =
  Arg.parse
    [
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "initialization 1";
            exit 0),
        "Print version" );
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected positional argument")),
        "End options" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected positional argument"))
    "initialization [--version]";
  let inverse = Sys.opaque_identity Morphiq_risk.Normal.norm_inv in
  if inverse 0.5 <> 0. then failwith "inverse midpoint";
  Gc.full_major ();
  let stats = Gc.stat () in
  Printf.printf "live_words,heap_words\n%d,%d\n" stats.live_words
    stats.heap_words
