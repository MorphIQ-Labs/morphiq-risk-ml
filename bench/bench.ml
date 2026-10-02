(* Throughput: nanoseconds per operation for each served quantity and model,
   over fixed-seed contracts in three regimes. The median of 7 timed runs
   follows a warm-up; each run evaluates every contract once.

     dune exec --release bench/bench.exe

   The numbers are for the machine that runs this. docs/performance.md
   records them with the machine and compiler. *)

open Morphiq_risk

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)
let n = 20_000

type regime = { name : string; z : unit -> float }

let regimes rng =
  [
    { name = "near the money"; z = (fun () -> Random.State.float rng 0.6 -. 0.3) };
    { name = "OTM tail"; z = (fun () -> 3.0 +. Random.State.float rng 5.0) };
    { name = "in the money"; z = (fun () -> -.(1.5 +. Random.State.float rng 2.0)) };
  ]

(* Contracts with log-moneyness z standard deviations from the forward. *)
let contracts rng regime =
  Array.init n (fun i ->
      let call = i land 1 = 0 in
      let s = Float.exp (Random.State.float rng 6.0 -. 3.0) in
      let t = Float.exp (Random.State.float rng 5.0 -. 4.0) in
      let sigma = 0.05 +. Random.State.float rng 0.6 in
      let r = Random.State.float rng 0.08 -. 0.02 and q = Random.State.float rng 0.05 in
      let z = regime.z () *. if call then 1.0 else -1.0 in
      let k = s *. Float.exp ((r -. q) *. t) *. Float.exp (z *. sigma *. Float.sqrt t) in
      (call, s, k, t, r, q, sigma))

let time f =
  let runs =
    Array.init 8 (fun i ->
        let t0 = Unix.gettimeofday () in
        f ();
        let dt = Unix.gettimeofday () -. t0 in
        if i = 0 then Float.nan else dt)
  in
  let runs = Array.sub runs 1 7 in
  Array.sort compare runs;
  runs.(3) /. float n *. 1e9

let sink = ref 0.0

let row model regime quantity ns = Printf.printf "| %s | %s | %s | %.0f |\n%!" model regime quantity ns

let () =
  let rng = Random.State.make [| 20261007 |] in
  print_endline "| Model | Regime | Quantity | ns/op |";
  print_endline "| --- | --- | --- | ---: |";
  List.iter
    (fun regime ->
      let cs = contracts rng regime in
      let side call = if call then Side.Call else Side.Put in
      let bsm =
        Array.map
          (fun (call, s, k, t, r, q, sigma) ->
            (get (Black.Bsm.admit { spot = s; strike = k; time_to_expiry = t; rate = r; dividend_yield = q }), side call, get (Vol.lognormal sigma)))
          cs
      in
      let prices = Array.map (fun (a, sd, v) -> Black.Bsm.price a sd v) bsm in
      row "BSM" regime.name "admit"
        (time (fun () ->
             Array.iter
               (fun (_, s, k, t, r, q, _) ->
                 match Black.Bsm.admit { spot = s; strike = k; time_to_expiry = t; rate = r; dividend_yield = q } with
                 | Ok _ -> sink := !sink +. 1.0
                 | Error _ -> ())
               cs));
      row "BSM" regime.name "price" (time (fun () -> Array.iter (fun (a, sd, v) -> sink := !sink +. Black.Bsm.price a sd v) bsm));
      row "BSM" regime.name "implied volatility"
        (time (fun () ->
             Array.iteri
               (fun i (a, sd, _) -> match Black.Bsm.implied a sd prices.(i) with Ok (Iv.Root v) -> sink := !sink +. Vol.to_float v | _ -> ())
               bsm));
      row "BSM" regime.name "all ten Greeks"
        (time (fun () ->
             Array.iter (fun (a, sd, v) -> match (Black.Bsm.greeks a sd v).delta with Ok d -> sink := !sink +. d | Error _ -> ()) bsm));
      let bach =
        Array.map
          (fun (call, s, k, t, r, _, sigma) ->
            (get (Bachelier.admit { forward = s; strike = k; time_to_expiry = t; rate = r }), side call, get (Vol.normal (sigma *. s))))
          cs
      in
      let bprices = Array.map (fun (a, sd, v) -> Bachelier.price a sd v) bach in
      row "Bachelier" regime.name "price" (time (fun () -> Array.iter (fun (a, sd, v) -> sink := !sink +. Bachelier.price a sd v) bach));
      row "Bachelier" regime.name "implied volatility"
        (time (fun () ->
             Array.iteri
               (fun i (a, sd, _) -> match Bachelier.implied a sd bprices.(i) with Ok (Iv.Root v) -> sink := !sink +. Vol.to_float v | _ -> ())
               bach));
      row "Bachelier" regime.name "all ten Greeks"
        (time (fun () ->
             Array.iter (fun (a, sd, v) -> match (Bachelier.greeks a sd v).delta with Ok d -> sink := !sink +. d | Error _ -> ()) bach)))
    (regimes rng);
  (* What determinism costs: the library's exp/log against the platform libm. *)
  let xs = Array.init n (fun i -> (float i /. float n *. 40.0) -. 20.0) in
  let ys = Array.map (fun x -> Float.exp x) xs in
  row "elementary" "-" "Elementary.exp" (time (fun () -> Array.iter (fun x -> sink := !sink +. Internal.Elementary.exp x) xs));
  row "elementary" "-" "libm exp" (time (fun () -> Array.iter (fun x -> sink := !sink +. Float.exp x) xs));
  row "elementary" "-" "Elementary.log" (time (fun () -> Array.iter (fun y -> sink := !sink +. Internal.Elementary.log y) ys));
  row "elementary" "-" "libm log" (time (fun () -> Array.iter (fun y -> sink := !sink +. Float.log y) ys));
  if !sink = 42.0 then print_endline ""
