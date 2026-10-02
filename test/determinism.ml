(* Cross-platform determinism. Every served quantity (price, implied
   volatility, the ten Greeks) over a fixed corpus of contracts is written as
   binary64 bit patterns and hashed. The digest is committed in
   test/determinism.digest. CI runs this on Linux x86-64, Linux arm64 and
   macOS arm64; the same digest everywhere means every platform serves the
   same bits.

   The library uses no platform libm (Elementary), so the only sources of
   difference would be non-IEEE arithmetic or a compiler contracting a*b+c
   into an fma, which OCaml does not do. *)

open Morphiq_risk

let buf = Buffer.create (1 lsl 20)
let emit x = Buffer.add_string buf (Printf.sprintf "%016Lx\n" (Int64.bits_of_float x))
let emit_result = function Ok v -> emit v | Error _ -> Buffer.add_string buf "refused\n"

let emit_iv to_float = function
  | Ok (Iv.Root v) -> emit (to_float v)
  | Ok Iv.Below_intrinsic -> Buffer.add_string buf "below\n"
  | Ok Iv.Above_maximum -> Buffer.add_string buf "above\n"
  | Ok Iv.Not_identifiable_at_expiry -> Buffer.add_string buf "expiry\n"
  | Ok Iv.Below_smallest_volatility -> Buffer.add_string buf "smallest\n"
  | Error _ -> Buffer.add_string buf "refused\n"

let rate r = Result.map (fun v -> (v : Units.per_calendar_day Units.time_rate :> float)) r
let per_vol r = Result.map (fun v -> (v : _ Units.per_volatility :> float)) r
let per_vol2 r = Result.map (fun v -> (v : _ Units.per_volatility_squared :> float)) r

let emit_greeks (g : _ Greeks.t) =
  emit_result g.delta;
  emit_result g.gamma;
  emit_result (rate g.theta);
  emit_result (per_vol g.vega);
  emit_result g.rho;
  emit_result (per_vol g.vanna);
  emit_result (per_vol2 g.volga);
  emit_result (rate g.charm);
  emit_result (rate g.veta);
  emit_result (rate g.color)

let lognormal s = Result.get_ok (Vol.lognormal s)
let normal s = Result.get_ok (Vol.normal s)

let () =
  let spots = [ 1e-150; 0.0123; 0.9; 1.0; 1.05; 37.5; 1e5; 1e150 ] in
  let moneyness = [ -3.0; -0.5; -1e-3; 0.0; 1e-3; 0.5; 3.0 ] in
  let times = [ 0.0; 1e-6; 1.0 /. 365.0; 0.25; 2.0; 30.0 ] in
  let sigmas = [ 0.0; 1e-6; 0.05; 0.3; 2.0 ] in
  let rates = [ (-0.01, 0.02); (0.03, 0.01); (0.05, 0.05) ] in
  List.iter
    (fun spot ->
      List.iter
        (fun m ->
          let strike = spot *. Internal.Elementary.exp m in
          List.iter
            (fun t ->
              List.iter
                (fun (r, q) ->
                  List.iter
                    (fun side ->
                      List.iter
                        (fun sigma ->
                          (match Black.Bsm.admit { spot; strike; time_to_expiry = t; rate = r; dividend_yield = q } with
                          | Ok a ->
                              let p = Black.Bsm.price a side (lognormal sigma) in
                              emit p;
                              emit_iv Vol.to_float (Black.Bsm.implied a side p);
                              emit_greeks (Black.Bsm.greeks a side (lognormal sigma))
                          | Error _ -> Buffer.add_string buf "refused\n");
                          (match
                             Black.Displaced.admit
                               { forward = spot -. 0.01; strike; displacement = 0.03; time_to_expiry = t; rate = r }
                           with
                          | Ok a ->
                              let p = Black.Displaced.price a side (lognormal sigma) in
                              emit p;
                              emit_iv Vol.to_float (Black.Displaced.implied a side p);
                              emit_greeks (Black.Displaced.greeks a side (lognormal sigma))
                          | Error _ -> Buffer.add_string buf "refused\n");
                          match Bachelier.admit { forward = spot; strike; time_to_expiry = t; rate = r } with
                          | Ok a ->
                              let s = sigma *. Float.max 1e-3 (Float.abs spot) in
                              let p = Bachelier.price a side (normal s) in
                              emit p;
                              emit_iv Vol.to_float (Bachelier.implied a side p);
                              emit_greeks (Bachelier.greeks a side (normal s))
                          | Error _ -> Buffer.add_string buf "refused\n")
                        sigmas)
                    [ Side.Call; Side.Put ])
                rates)
            times)
        moneyness)
    spots;
  let bytes = Buffer.length buf in
  let digest = Digest.BLAKE256.to_hex (Digest.BLAKE256.string (Buffer.contents buf)) in
  let expected = String.trim (In_channel.with_open_text Sys.argv.(1) In_channel.input_all) in
  Printf.printf "determinism digest %s over %d bytes\n" digest bytes;
  if digest <> expected then (
    Printf.printf "expected %s: this platform serves different bits\n" expected;
    exit 1)
