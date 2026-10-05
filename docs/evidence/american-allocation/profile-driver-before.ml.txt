open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "profile request failed"
let calls = ref 1
let mode = ref "cash"

let () =
  Arg.parse
    [
      ("--calls", Arg.Set_int calls, "Number of American price calls");
      ("--mode", Arg.Set_string mode, "none, zero, cash, multiple");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "american-allocation-profile-v1";
            exit 0),
        "Print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Estimated American allocation sampling";
  if !calls < 1 then (
    prerr_endline "calls must be positive";
    exit 2);
  let module A = Early_exercise.Bsm in
  let inputs =
    A.
      {
        spot = 100.;
        strike = 100.;
        rate = 0.05;
        dividend_yield = 0.02;
        time_to_expiry = 1.;
        opens_at = 0.;
        volatility = get (Vol.lognormal 0.2);
      }
  in
  let admitted =
    match !mode with
    | "none" -> get (A.admit inputs)
    | "zero" | "cash" | "multiple" ->
        let dividends =
          if !mode = "multiple" then
            [| A.{ time = 0.25; amount = 3. }; A.{ time = 0.75; amount = 4. } |]
          else
            [| A.{ time = 0.5; amount = (if !mode = "zero" then 0. else 5.) } |]
        in
        get
          (A.admit_cash inputs
             {
               valuation_side = Regular;
               opening_side = Regular;
               expiry_side = Regular;
               dividends;
             })
    | _ -> invalid_arg "mode"
  in
  let cfg =
    get
      (A.configure ~tolerance:1. ~space_cells:128 ~time_steps:128
         ~domain_expansions:2
         ~limits:
           {
             max_nodes = 8192;
             max_steps = 131072;
             max_policy_solves = 1048576;
             max_row_visits = 1000000000;
             max_workspace_bytes = 8388608;
             policy_iterations = 64;
           })
  in
  let price () = get (A.price cfg admitted Side.Put) in
  for _ = 1 to 1 do
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
    Gc.Memprof.start ~sampling_rate:0.0001 ~callstack_size:12
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
           (float n *. 8. /. 0.0001 /. float !calls)
           stack)
