open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "admission"
let sink = ref 0.

let measure label n f =
  let samples =
    Array.init 8 (fun _ ->
        let start = Unix.gettimeofday () in
        for _ = 1 to n do
          sink := Sys.opaque_identity (f ())
        done;
        (Unix.gettimeofday () -. start) *. 1e9 /. float n)
  in
  Printf.printf "%s %s\n%!" label
    (String.concat ","
       (Array.to_list
          (Array.map (Printf.sprintf "%.3f") (Array.sub samples 1 7))))

let bench label s k r sigma n =
  let input =
    Black.Bsm_carry.
      {
        spot = s;
        strike = k;
        time_to_expiry = 1.;
        rate = r;
        dividend_yield = 0.;
      }
  in
  let v = get (Vol.lognormal sigma) and a = get (Black.Bsm.admit input) in
  let greek a =
    let g = Sys.opaque_identity (Black.Bsm.greeks a Side.Call v) in
    match g.delta with Ok v -> v | Error _ -> -1.
  in
  measure (label ^ "/admission") 10000 (fun () ->
      ignore (Sys.opaque_identity (get (Black.Bsm.admit input)));
      1.);
  measure (label ^ "/price") n (fun () -> Black.Bsm.price a Side.Call v);
  measure (label ^ "/greeks") n (fun () -> greek a);
  measure (label ^ "/admission+greeks") n (fun () ->
      greek (get (Black.Bsm.admit input)))

let () =
  Arg.parse
    [
      ( "--replay-factors",
        Arg.Unit
          (fun () ->
            List.iter
              (fun m ->
                Printf.printf "%016Lx\n"
                  (Int64.bits_of_float (Internal.Elementary.exp m)))
              [ -3.; -0.5; -1e-3; 0.; 1e-3; 0.5; 3. ];
            exit 0),
        "Emit original binary64 moneyness factors used by the public replay" );
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline Morphiq_risk.version;
            exit 0),
        "Library version" );
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected argument")),
        "End options" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "greek_cancellation: separate admission, price and all-Greek timings";
  bench "ordinary-positive" 100. 95. 0.02 0.2 10000;
  bench "ordinary-zero" 100. 95. 0.02 0. 10000;
  List.iter
    (fun (name, sigma) ->
      bench name (Float.succ 1.) 1.
        (Int64.float_of_bits 0xbcafffffffffffffL)
        sigma 100)
    [ ("cancel-zero", 0.); ("cancel-positive", 0.2); ("cancel-tiny", 0x1p-160) ];
  ignore (Sys.opaque_identity !sink)
