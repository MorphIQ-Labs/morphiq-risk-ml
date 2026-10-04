open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "admission"
let sink = ref 0.

let measure label n f =
  let times =
    Array.init 8 (fun _ ->
        let start = Unix.gettimeofday () in
        for _ = 1 to n do
          sink := Sys.opaque_identity (f ())
        done;
        (Unix.gettimeofday () -. start) *. 1e9 /. float n)
  in
  Printf.printf "%s %s\n%!" label
    (String.concat ","
       (Array.to_list (Array.map (Printf.sprintf "%.3f") (Array.sub times 1 7))))

let bench label s k t r q sigma n =
  let input =
    Black.Bsm_carry.
      { spot = s; strike = k; time_to_expiry = t; rate = r; dividend_yield = q }
  in
  let a = get (Black.Bsm.admit input) and v = get (Vol.lognormal sigma) in
  let greek a =
    let g = Sys.opaque_identity (Black.Bsm.greeks a Side.Call v) in
    match g.rho with Ok x -> x | Error _ -> -1.
  in
  measure (label ^ "/admission") 10000 (fun () ->
      ignore (Sys.opaque_identity (Black.Bsm.admit input));
      1.);
  measure (label ^ "/price") n (fun () -> Black.Bsm.price a Side.Call v);
  measure (label ^ "/greeks") n (fun () -> greek a);
  measure (label ^ "/admission+greeks") n (fun () ->
      greek (get (Black.Bsm.admit input)))

let () =
  Arg.parse
    [
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
    "rho_midpoint: separate operation costs";
  bench "ordinary" 100. 95. 1. 0.02 0. 0.2 10000;
  bench "ordinary-zero-otm" 95. 100. 1. 0.02 0. 0. 200;
  bench "midpoint" 1. 1. 0x1p-1074 0. 0. 0.25 200;
  bench "tiny-zero" 2. 1. 0x1p-1074 0. 0. 0. 200;
  bench "zero-tail" 1. 100. 1. 0. 0. 0.05 200;
  ignore (Sys.opaque_identity !sink)
