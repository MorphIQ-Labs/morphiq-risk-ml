open Morphiq_risk

let ok = function Ok x -> x | Error _ -> failwith "profile refusal"
let calls = ref 2000
let model = ref "bsm"
let phase = ref "execute"

let () =
  Arg.parse
    [
      ("--calls", Arg.Set_int calls, "Calls per phase");
      ("--model", Arg.Set_string model, "bsm, black76, displaced, bachelier");
      ("--phase", Arg.Set_string phase, "compile, execute, run");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "fast-allocation-profile-v1";
            exit 0),
        "Version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Fast pricing allocation sampling";
  if !calls < 1 then invalid_arg "calls";
  let sigma = ok (Vol.lognormal 0.2) in
  let request =
    match !model with
    | "bsm" ->
        Batch.Fast.Price
          ( Batch.Bsm,
            {
              spot = 100.;
              strike = 95.;
              time_to_expiry = 1.;
              rate = 0.02;
              dividend_yield = 0.01;
            },
            Side.Call,
            sigma )
    | "black76" ->
        Batch.Fast.Price
          ( Batch.Black76,
            { forward = 100.; strike = 95.; time_to_expiry = 1.; rate = 0.02 },
            Side.Call,
            sigma )
    | "displaced" ->
        Batch.Fast.Price
          ( Batch.Displaced,
            {
              forward = -2.;
              strike = -1.;
              displacement = 5.;
              time_to_expiry = 1.;
              rate = 0.02;
            },
            Side.Call,
            sigma )
    | "bachelier" ->
        Batch.Fast.Price
          ( Batch.Bachelier,
            { forward = -2.; strike = -1.; time_to_expiry = 1.; rate = 0.02 },
            Side.Call,
            ok (Vol.normal 2.) )
    | _ -> invalid_arg "model"
  in
  let requests = [| request |] in
  let prepared = Batch.Fast.compile requests in
  let work =
    match !phase with
    | "compile" ->
        fun () -> ignore (Sys.opaque_identity (Batch.Fast.compile requests))
    | "execute" ->
        fun () -> ignore (Sys.opaque_identity (Batch.Fast.execute prepared))
    | "run" -> fun () -> ignore (Sys.opaque_identity (Batch.Fast.run requests))
    | _ -> invalid_arg "phase"
  in
  let result = (Batch.Fast.execute prepared).(0) in
  ignore (ok result);
  for _ = 1 to 5 do
    work ()
  done;
  let words () =
    let a, b, c = Gc.counters () in
    a +. c -. b
  in
  Gc.full_major ();
  let before = words () in
  for _ = 1 to !calls do
    work ()
  done;
  Printf.printf "MODEL %s PHASE %s BYTES_PER_CALL %.1f OUTCOME %Lx\n%!" !model
    !phase
    (8. *. (words () -. before) /. float !calls)
    (Int64.bits_of_float (ok result));
  let sites = Hashtbl.create 100 in
  let alloc (a : Gc.Memprof.allocation) =
    let key = Printexc.raw_backtrace_to_string a.callstack in
    let n = Option.value ~default:0 (Hashtbl.find_opt sites key) in
    Hashtbl.replace sites key (n + a.n_samples);
    None
  in
  let profile =
    Gc.Memprof.start ~sampling_rate:0.01 ~callstack_size:16
      { Gc.Memprof.null_tracker with alloc_minor = alloc; alloc_major = alloc }
  in
  for _ = 1 to !calls do
    work ()
  done;
  Gc.Memprof.stop ();
  Gc.Memprof.discard profile;
  Hashtbl.to_seq sites |> List.of_seq
  |> List.sort (fun (_, a) (_, b) -> compare b a)
  |> List.iter (fun (stack, n) ->
         Printf.printf "SAMPLES %d ESTIMATED_BYTES_PER_CALL %.1f\n%s\n" n
           (float n *. 8. /. 0.01 /. float !calls)
           stack)
