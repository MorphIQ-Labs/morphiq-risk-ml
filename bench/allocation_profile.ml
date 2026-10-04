open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "profile request failed"
let calls = ref 100

let () =
  Arg.parse
    [
      ("--calls", Arg.Set_int calls, "Number of certified price calls");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "allocation-profile-v1";
            exit 0),
        "Print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Certified BSM allocation sampling";
  if !calls < 1 then (
    prerr_endline "calls must be positive";
    exit 2);
  let a =
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
  let v = get (Vol.lognormal 0.2) in
  let price () =
    get (Production.Bsm.evaluate a Side.Call v Production.Price ~max_error:1e-9)
  in
  for _ = 1 to 5 do
    ignore (Sys.opaque_identity (price ()))
  done;
  let words () =
    let a, b, c = Gc.counters () in
    a +. c -. b
  in
  Gc.full_major ();
  let before = words () in
  for _ = 1 to !calls do
    ignore (Sys.opaque_identity (price ()))
  done;
  Printf.printf "UNPROFILED_BYTES_PER_CALL %.1f\n%!"
    (8. *. (words () -. before) /. float !calls);
  let sites = Hashtbl.create 100 in
  let alloc (a : Gc.Memprof.allocation) =
    let key = Printexc.raw_backtrace_to_string a.callstack in
    let n = match Hashtbl.find_opt sites key with Some n -> n | None -> 0 in
    Hashtbl.replace sites key (n + a.n_samples);
    None
  in
  let profile =
    Gc.Memprof.start ~sampling_rate:0.001 ~callstack_size:12
      { Gc.Memprof.null_tracker with alloc_minor = alloc; alloc_major = alloc }
  in
  for _ = 1 to !calls do
    ignore (Sys.opaque_identity (price ()))
  done;
  Gc.Memprof.stop ();
  Gc.Memprof.discard profile;
  Hashtbl.to_seq sites |> List.of_seq
  |> List.sort (fun (_, a) (_, b) -> compare b a)
  |> List.iter (fun (stack, n) ->
         Printf.printf "SAMPLES %d ESTIMATED_BYTES_PER_CALL %.1f\n%s\n" n
           (float n *. 8. /. 0.001 /. float !calls)
           stack)
