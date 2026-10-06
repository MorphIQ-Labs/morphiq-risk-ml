(* Remaining managed allocation in the frozen #147 singleton requests.
   Profiling and unprofiled counters are distinct phases; no profiler latency
   is reported as ordinary pricing cost. *)
module I = Backend_inputs

let words () =
  let minor, promoted, major = Gc.counters () in
  minor +. major -. promoted

let () =
  let case = ref "cash" and calls = ref 20 in
  Arg.parse
    [
      ("--case", Arg.Set_string case, "frozen workload");
      ("--calls", Arg.Set_int calls, "calls per phase (default 20)");
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected positional argument")),
        "end options" );
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "american-remaining-allocation 1";
            exit 0),
        "version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected positional argument"))
    "American remaining allocation attribution";
  if (not (List.mem !case I.cases)) || !calls < 1 then invalid_arg "case/calls";
  if Sys.getenv_opt "MORPHIQ_CAPTURE_CELLS" <> None then
    invalid_arg "frozen grid requires MORPHIQ_CAPTURE_CELLS unset";
  let item = I.make_item !case 0 in
  let (I.B.Request r) = item.request ~offset:0 ~spot:100. in
  let request = I.B.Request { r with id = "0" } in
  let operation () = I.scalar request in
  let reference = operation () in
  let expected = I.digest reference in
  Gc.full_major ();
  let before = words () in
  for _ = 1 to !calls do
    ignore (Sys.opaque_identity (operation ()))
  done;
  let bytes = 8. *. (words () -. before) /. float !calls in
  Printf.printf "BASELINE\t%s\t%d\t%s\t%.17g\n%!" !case !calls expected bytes;
  let sites = Hashtbl.create 128 in
  let sample (a : Gc.Memprof.allocation) =
    let stack = Printexc.raw_backtrace_to_string a.callstack in
    let n = Option.value ~default:0 (Hashtbl.find_opt sites stack) in
    Hashtbl.replace sites stack (n + a.n_samples);
    None
  in
  Gc.full_major ();
  let profile =
    Gc.Memprof.start ~sampling_rate:0.0001 ~callstack_size:20
      {
        Gc.Memprof.null_tracker with
        alloc_minor = sample;
        alloc_major = sample;
      }
  in
  for _ = 1 to !calls do
    ignore (Sys.opaque_identity (operation ()))
  done;
  Gc.Memprof.stop ();
  Gc.Memprof.discard profile;
  if I.digest (operation ()) <> expected then failwith "changed request replay";
  Hashtbl.to_seq sites |> List.of_seq
  |> List.sort (fun (_, a) (_, b) -> compare b a)
  |> List.iter (fun (stack, n) -> Printf.printf "SAMPLES %d\n%s\n" n stack);
  Printf.printf "COMPLETE\t%s\t%d\n%!" !case !calls
