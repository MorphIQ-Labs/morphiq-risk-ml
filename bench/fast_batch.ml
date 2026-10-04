open Morphiq_risk
module F = Batch.Fast

external monotonic : unit -> float = "morphiq_bench_monotonic"

let get = function Ok x -> x | Error _ -> failwith "benchmark admission"
let sigma = get (Vol.lognormal 0.2)
let normal = get (Vol.normal 2.)

let request i =
  let side = if i / 4 mod 2 = 0 then Side.Call else Side.Put in
  let strike = 95. +. float (i mod 11) in
  match i mod 4 with
  | 0 ->
      F.Price
        ( Batch.Bsm,
          {
            spot = 100.;
            strike;
            time_to_expiry = 1.;
            rate = 0.02;
            dividend_yield = 0.01;
          },
          side,
          sigma )
  | 1 ->
      F.Price
        ( Batch.Black76,
          { forward = 100.; strike; time_to_expiry = 1.; rate = 0.02 },
          side,
          sigma )
  | 2 ->
      F.Price
        ( Batch.Displaced,
          {
            forward = -2.;
            strike = strike -. 100.;
            displacement = 10.;
            time_to_expiry = 1.;
            rate = 0.02;
          },
          side,
          sigma )
  | _ ->
      F.Price
        ( Batch.Bachelier,
          {
            forward = -2.;
            strike = strike -. 100.;
            time_to_expiry = 1.;
            rate = 0.02;
          },
          side,
          normal )

let checked value =
  if Float.is_finite value && value >= 0. then Ok value
  else Error F.Numerical_failure

let scalar (F.Price (model, inputs, side, vol)) =
  match model with
  | Batch.Bsm ->
      checked (Black.Bsm.price (get (Black.Bsm.admit inputs)) side vol)
  | Batch.Black76 ->
      checked (Black.Black76.price (get (Black.Black76.admit inputs)) side vol)
  | Batch.Displaced ->
      checked
        (Black.Displaced.price (get (Black.Displaced.admit inputs)) side vol)
  | Batch.Bachelier ->
      checked (Bachelier.price (get (Bachelier.admit inputs)) side vol)

let preadmit (F.Price (model, inputs, side, vol)) =
  match model with
  | Batch.Bsm ->
      let a = get (Black.Bsm.admit inputs) in
      fun () -> checked (Black.Bsm.price a side vol)
  | Batch.Black76 ->
      let a = get (Black.Black76.admit inputs) in
      fun () -> checked (Black.Black76.price a side vol)
  | Batch.Displaced ->
      let a = get (Black.Displaced.admit inputs) in
      fun () -> checked (Black.Displaced.price a side vol)
  | Batch.Bachelier ->
      let a = get (Bachelier.admit inputs) in
      fun () -> checked (Bachelier.price a side vol)

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let sample n phase f =
  let iterations = max 1 (8192 / n) in
  for _ = 1 to 3 do
    ignore (Sys.opaque_identity (f ()))
  done;
  for round = 1 to 5 do
    Gc.full_major ();
    let before = words () and cpu = Sys.time () and start = monotonic () in
    for _ = 1 to iterations do
      ignore (Sys.opaque_identity (f ()))
    done;
    let elapsed = monotonic () -. start in
    let cpu = Sys.time () -. cpu and bytes = 8. *. (words () -. before) in
    Printf.printf "TIME %d %s %d %.3f %.3f %.3f\n%!" n phase round
      (elapsed *. 1e9 /. float iterations)
      (cpu *. 1e9 /. float iterations)
      (bytes /. float iterations)
  done

let () =
  Arg.parse
    [
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "fast-batch-v1";
            exit 0),
        "Print version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Fast batch phase benchmark";
  List.iter
    (fun n ->
      let inputs = Array.init n request in
      let plan = F.compile inputs and admitted = Array.map preadmit inputs in
      let expected = Array.map scalar inputs in
      let serialized = Marshal.to_string expected [] in
      List.iter
        (fun got ->
          if Marshal.to_string got [] <> serialized then
            failwith "outcome mismatch")
        [ F.run inputs; F.execute plan; Array.map (fun f -> f ()) admitted ];
      Printf.printf "CHECK %d %s\n%!" n
        (Digest.to_hex (Digest.string serialized));
      sample n "scalar-admit-price" (fun () -> Array.map scalar inputs);
      sample n "scalar-preadmitted" (fun () ->
          Array.map (fun f -> f ()) admitted);
      sample n "compile" (fun () -> F.compile inputs);
      sample n "execute" (fun () -> F.execute plan);
      sample n "one-shot" (fun () -> F.run inputs);
      sample n "pack-compile-execute-extract" (fun () ->
          let results = F.execute (F.compile (Array.init n request)) in
          Array.map
            (function Ok x -> x | Error _ -> failwith "unexpected failure")
            results))
    [ 32; 256; 1024 ]
