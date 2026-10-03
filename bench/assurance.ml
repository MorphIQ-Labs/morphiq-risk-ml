(* Manual benchmark: performance evidence, never an accuracy or SLA gate.
   Quantities are timed separately; all IV outcomes are counted before timing.
   The same source runs against the proposal-only baseline and certified IV. *)
open Morphiq_risk

external monotonic : unit -> float = "morphiq_bench_monotonic"

let get = function Ok x -> x | Error e -> failwith (Refusal.to_string e)
let n = ref 64
let runs = ref 5
let black_box x = ignore (Sys.opaque_identity x)

let allocated_words () =
  let minor, promoted, major = Gc.counters () in
  minor +. major -. promoted

let measurement_controls () =
  let before = allocated_words () in
  black_box (Array.make 10_000 0.0);
  if allocated_words () -. before < 10_001.0 then
    failwith "allocation counter misses a known allocation";
  let before = monotonic () in
  if monotonic () < before then failwith "monotonic clock moved backward"

type case = {
  admit : unit -> unit;
  price : unit -> unit;
  iv : unit -> unit;
  greeks : unit -> unit;
  all : unit -> unit;
  outcome : string;
}

let outcome = function
  | Error _ -> "refusal"
  | Ok (Iv.Root v) -> if Vol.to_float v = 0.0 then "zero" else "root"
  | Ok Iv.Below_intrinsic -> "below_intrinsic"
  | Ok Iv.Above_maximum -> "above_maximum"
  | Ok Iv.Not_identifiable_at_expiry -> "expiry"
  | Ok Iv.Below_smallest_volatility -> "below_smallest"
  | Ok Iv.Non_convergence -> "non_convergence"
  | Ok Iv.Numerical_failure -> "numerical_failure"

let prepare ~admit ~price ~implied ~greeks ~vol side =
  let a = get (admit ()) in
  let quote = price a side vol in
  if not (Float.is_finite quote && quote >= 0.0) then
    failwith "nonfinite benchmark quote";
  {
    admit = (fun () -> black_box (get (admit ())));
    price = (fun () -> black_box (price a side vol));
    iv = (fun () -> black_box (implied a side quote));
    greeks = (fun () -> black_box (greeks a side vol));
    all =
      (fun () ->
        let admitted = get (admit ()) in
        let p = price admitted side vol in
        black_box (implied admitted side p);
        black_box (greeks admitted side vol));
    outcome = outcome (implied a side quote);
  }

let cases model regime =
  let rng = Random.State.make [| 27; 14; 20261002 |] in
  Array.init !n (fun i ->
      let s = Float.exp (Random.State.float rng 6.0 -. 3.0) in
      let t = Float.exp (Random.State.float rng 5.0 -. 4.0) in
      let sigma = 0.05 +. Random.State.float rng 0.6 in
      let r = Random.State.float rng 0.08 -. 0.02 in
      let q = Random.State.float rng 0.05 in
      let side = if i land 1 = 0 then Side.Call else Side.Put in
      let z =
        match regime with
        | "atm" -> Random.State.float rng 0.6 -. 0.3
        | "otm" -> 3.0 +. Random.State.float rng 5.0
        | _ -> -.(1.5 +. Random.State.float rng 2.0)
      in
      let z = z *. Side.sign side in
      let k = s *. Float.exp (z *. sigma *. Float.sqrt t) in
      match model with
      | "bsm" ->
          let strike = k *. Float.exp ((r -. q) *. t) in
          prepare
            ~admit:(fun () ->
              Black.Bsm.admit
                {
                  spot = s;
                  strike;
                  time_to_expiry = t;
                  rate = r;
                  dividend_yield = q;
                })
            ~price:Black.Bsm.price ~implied:Black.Bsm.implied
            ~greeks:Black.Bsm.greeks
            ~vol:(get (Vol.lognormal sigma))
            side
      | "black76" ->
          prepare
            ~admit:(fun () ->
              Black.Black76.admit
                { forward = s; strike = k; time_to_expiry = t; rate = r })
            ~price:Black.Black76.price ~implied:Black.Black76.implied
            ~greeks:Black.Black76.greeks
            ~vol:(get (Vol.lognormal sigma))
            side
      | "displaced" ->
          prepare
            ~admit:(fun () ->
              Black.Displaced.admit
                {
                  forward = s -. 2.0;
                  strike = k -. 2.0;
                  displacement = 2.0;
                  time_to_expiry = t;
                  rate = r;
                })
            ~price:Black.Displaced.price ~implied:Black.Displaced.implied
            ~greeks:Black.Displaced.greeks
            ~vol:(get (Vol.lognormal sigma))
            side
      | _ ->
          let strike = s +. (z *. sigma *. s *. Float.sqrt t) in
          prepare
            ~admit:(fun () ->
              Bachelier.admit
                { forward = s; strike; time_to_expiry = t; rate = r })
            ~price:Bachelier.price ~implied:Bachelier.implied
            ~greeks:Bachelier.greeks
            ~vol:(get (Vol.normal (sigma *. s)))
            side)

let percentile fraction values =
  let sorted = Array.copy values in
  Array.sort Float.compare sorted;
  sorted.(int_of_float (Float.ceil (fraction *. float (Array.length sorted)))
          - 1)

let measure operations =
  let gc_before = Gc.quick_stat () in
  let words_before = allocated_words () in
  let cpu = Sys.time () and start = monotonic () in
  Array.iter (fun f -> f ()) operations;
  let elapsed = monotonic () -. start and cpu = Sys.time () -. cpu in
  let words_after = allocated_words () in
  let gc_after = Gc.quick_stat () in
  ( elapsed *. 1e9 /. float !n,
    cpu *. 1e9 /. float !n,
    (words_after -. words_before) /. float !n,
    gc_after.Gc.minor_collections - gc_before.Gc.minor_collections,
    gc_after.Gc.major_collections - gc_before.Gc.major_collections,
    gc_after.Gc.heap_words )

let row model regime quantity operations =
  let cold, _, _, _, _, _ = measure operations in
  let samples = Array.init !runs (fun _ -> measure operations) in
  let times = Array.map (fun (x, _, _, _, _, _) -> x) samples in
  let cpus = Array.map (fun (_, x, _, _, _, _) -> x) samples in
  let words = Array.map (fun (_, _, x, _, _, _) -> x) samples in
  let minor, major, heap =
    Array.fold_left
      (fun (a, b, h) (_, _, _, x, y, z) -> (a + x, b + y, max h z))
      (0, 0, 0) samples
  in
  (* Separate per-request sampling includes two clock reads, dispatch and GC. *)
  let latency =
    Array.map
      (fun f ->
        let t = monotonic () in
        f ();
        (monotonic () -. t) *. 1e9)
      operations
  in
  Printf.printf
    "%s,%s,%s,%d,%d,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%d,%d,%d,%.0f,%.0f,%.0f\n%!"
    model regime quantity !n !runs cold (percentile 0.5 times)
    (Array.fold_left min infinity times)
    (Array.fold_left max 0.0 times)
    (percentile 0.5 cpus) (percentile 0.5 words) minor major heap
    (percentile 0.5 latency) (percentile 0.95 latency) (percentile 0.99 latency)

let () =
  Arg.parse
    [
      ("--count", Arg.Set_int n, "Contracts per model/regime (default 64)");
      ("--runs", Arg.Set_int runs, "Warm batches (default 5)");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline version;
            exit 0),
        "Library version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected positional argument"))
    "assurance [--count N] [--runs N]";
  if !n <= 0 || !runs <= 0 then (
    prerr_endline "count and runs must be positive";
    exit 2);
  measurement_controls ();
  print_endline
    "model,regime,quantity,count,runs,first_batch_ns,median_ns,min_ns,max_ns,cpu_ns,allocated_words,minor_collections,major_collections,heap_words,p50_request_ns,p95_request_ns,p99_request_ns";
  row "harness" "empty" "dispatch_clock"
    (Array.make !n (fun () -> black_box ()));
  List.iter
    (fun model ->
      List.iter
        (fun regime ->
          let cs = cases model regime in
          let statuses = Hashtbl.create 8 in
          Array.iter
            (fun c ->
              Hashtbl.replace statuses c.outcome
                (1
                + Option.value ~default:0 (Hashtbl.find_opt statuses c.outcome)
                ))
            cs;
          Hashtbl.to_seq statuses |> List.of_seq |> List.sort compare
          |> List.iter (fun (status, count) ->
                 Printf.eprintf "%s %s %s %d/%d\n%!" model regime status count
                   !n);
          List.iter
            (fun (quantity, extract) ->
              row model regime quantity (Array.map extract cs))
            [
              ("admission", fun c -> c.admit);
              ("price", fun c -> c.price);
              ("iv", fun c -> c.iv);
              ("greeks", fun c -> c.greeks);
              ("end_to_end", fun c -> c.all);
            ])
        [ "atm"; "otm"; "itm" ])
    [ "bsm"; "black76"; "displaced"; "bachelier" ]
