open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "admission"
let sigma = get (Vol.lognormal 0.)
let ordinary = get (Vol.lognormal 0.2)

let inputs s k r =
  Black.Bsm_carry.
    { spot = s; strike = k; time_to_expiry = 1.; rate = r; dividend_yield = 0. }

let result = ref 0.

let bench label n input vol =
  let admitted = get (Black.Bsm.admit input) in
  let run f =
    let times =
      Array.init 8 (fun _ ->
          let start = Unix.gettimeofday () in
          for _ = 1 to n do
            result := Sys.opaque_identity (f ())
          done;
          (Unix.gettimeofday () -. start) *. 1e9 /. float n)
    in
    let measured = Array.sub times 1 7 in
    Printf.printf "%s %s\n%!" label
      (String.concat ","
         (Array.to_list (Array.map (Printf.sprintf "%.3f") measured)))
  in
  run (fun () -> Black.Bsm.price admitted Side.Call vol)

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
    "carry_cancellation: manual price benchmark";
  bench "ordinary-positive" 100000 (inputs 100. 95. 0.02) ordinary;
  bench "ordinary-zero" 100000 (inputs 100. 95. 0.02) sigma;
  bench "cancel-zero" 2000
    (inputs (Float.succ 1.) 1. (Int64.float_of_bits 0xbcafffffffffffffL))
    sigma;
  bench "cancel-positive" 2000
    (inputs (Float.succ 1.) 1. (Int64.float_of_bits 0xbcafffffffffffffL))
    ordinary;
  ignore (Sys.opaque_identity !result)
