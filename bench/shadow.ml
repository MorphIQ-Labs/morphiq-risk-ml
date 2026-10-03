(* Optional captured-input shadow worker. Text protocol uses exact binary64
   words; no JSON or arbitrary precision dependency enters the library. *)
open Morphiq_risk
module P = Production

external monotonic : unit -> float = "morphiq_bench_monotonic"

let word x = Printf.sprintf "%016Lx" (Int64.bits_of_float x)
let float s = Int64.float_of_bits (Int64.of_string ("0x" ^ s))

let error = function
  | P.Invalid_input r -> "invalid_input:" ^ Refusal.to_string r
  | P.Invalid_accuracy -> "invalid_accuracy"
  | P.Unsupported P.Expiry_greek -> "unsupported_expiry_greek"
  | P.Unsupported P.Zero_volatility_greek -> "unsupported_zero_volatility_greek"
  | P.Numerical_failure -> "numerical_failure"
  | P.Accuracy_exceeded -> "accuracy_exceeded"

type 'c request =
  | Request : string * ('c, 'a) P.quantity * 'a * ('a -> float) -> 'c request

let requests : type c. float -> c request list =
 fun limit ->
  [
    Request ("price", P.Price, limit, Fun.id);
    Request ("delta", P.Delta, limit, Fun.id);
    Request ("gamma", P.Gamma, limit, Fun.id);
    Request ("rho", P.Rho, limit, Fun.id);
    Request ("theta", P.Theta, Units.time_rate limit, fun x -> (x :> float));
    Request ("vega", P.Vega, Units.per_volatility limit, fun x -> (x :> float));
    Request ("vanna", P.Vanna, Units.per_volatility limit, fun x -> (x :> float));
    Request
      ( "volga",
        P.Volga,
        Units.per_volatility_squared limit,
        fun x -> (x :> float) );
    Request ("charm", P.Charm, Units.time_rate limit, fun x -> (x :> float));
    Request
      ("veta", P.Veta, Units.volatility_time_rate limit, fun x -> (x :> float));
    Request ("color", P.Color, Units.time_rate limit, fun x -> (x :> float));
  ]

let iv = function
  | Iv.Root v -> "root\t" ^ word (Vol.to_float v)
  | Iv.Below_intrinsic -> "below_intrinsic"
  | Iv.Above_maximum -> "above_maximum"
  | Iv.Not_identifiable_at_expiry -> "expiry"
  | Iv.Below_smallest_volatility -> "below_smallest_volatility"
  | Iv.Non_convergence -> "non_convergence"
  | Iv.Numerical_failure -> "numerical_failure"

module Run (M : sig
  include P.MODEL

  val vol : float -> (coordinate Vol.t, Refusal.t) result
end) =
struct
  let run inputs side sigma quote limit =
    match (M.admit inputs, M.vol sigma) with
    | Error e, _ -> [ ("admission", error e) ]
    | _, Error r -> [ ("admission", error (P.Invalid_input r)) ]
    | Ok admitted, Ok vol ->
        let values =
          List.map
            (fun (Request (name, quantity, max_error, raw)) ->
              let value =
                match M.evaluate admitted side vol quantity ~max_error with
                | Error e -> error e
                | Ok c ->
                    "ok\t"
                    ^ word (raw c.value)
                    ^ "\t"
                    ^ word (raw c.absolute_error)
              in
              (name, value))
            (requests limit)
        in
        let root =
          match M.implied admitted side quote with
          | Error e -> error e
          | Ok r -> iv r
        in
        (("admission", "ok") :: values) @ [ ("iv", root) ]
end

module B = Run (struct
  include P.Bsm

  let vol = Vol.lognormal
end)

module F = Run (struct
  include P.Black76

  let vol = Vol.lognormal
end)

module D = Run (struct
  include P.Displaced

  let vol = Vol.lognormal
end)

module N = Run (struct
  include P.Bachelier

  let vol = Vol.normal
end)

let evaluate fields =
  match fields with
  | [ id; model; side; s; k; t; r; q; sigma; shift; quote; limit ] ->
      let s, k, t, r, q, sigma, shift, quote, limit =
        ( float s,
          float k,
          float t,
          float r,
          float q,
          float sigma,
          float shift,
          float quote,
          float limit )
      in
      let side =
        match side with
        | "call" -> Side.Call
        | "put" -> Side.Put
        | _ -> failwith "side"
      in
      let values =
        match model with
        | "bsm" ->
            B.run
              {
                spot = s;
                strike = k;
                time_to_expiry = t;
                rate = r;
                dividend_yield = q;
              }
              side sigma quote limit
        | "black76" ->
            F.run
              { forward = s; strike = k; time_to_expiry = t; rate = r }
              side sigma quote limit
        | "displaced" ->
            D.run
              {
                forward = s;
                strike = k;
                time_to_expiry = t;
                rate = r;
                displacement = shift;
              }
              side sigma quote limit
        | "bachelier" ->
            N.run
              { forward = s; strike = k; time_to_expiry = t; rate = r }
              side sigma quote limit
        | _ -> failwith "model"
      in
      (id, values)
  | _ -> failwith "shadow row must have 12 tab-separated fields"

let () =
  if Array.length Sys.argv <> 1 then (
    if Array.to_list Sys.argv = [ Sys.argv.(0); "--help" ] then
      print_endline
        "shadow: read id/model/side/S/K/T/r/q/sigma/shift/quote/limit \
         tab-separated binary64-word rows from stdin"
    else if Array.to_list Sys.argv = [ Sys.argv.(0); "--version" ] then
      print_endline Morphiq_risk.version
    else (
      prerr_endline "shadow: no positional arguments; use --help";
      exit 2);
    exit 0);
  print_endline "READY";
  flush stdout;
  let rec read acc =
    match input_line stdin with
    | line -> read (String.split_on_char '\t' line :: acc)
    | exception End_of_file -> Array.of_list (List.rev acc)
  in
  let rows = read [] in
  let a0, b0, c0 = Gc.counters () in
  let gc0 = Gc.quick_stat () and cpu0 = Sys.time () and start = monotonic () in
  let results =
    Array.map
      (fun row ->
        let t0 = monotonic () in
        let result = evaluate row in
        (result, monotonic () -. t0))
      rows
  in
  let elapsed = monotonic () -. start
  and cpu = Sys.time () -. cpu0
  and gc1 = Gc.quick_stat () in
  let a1, b1, c1 = Gc.counters () in
  let probe_start = monotonic () in
  for _i = 1 to 10000 do
    ignore (Sys.opaque_identity (monotonic ()))
  done;
  let clock_probe = (monotonic () -. probe_start) /. 10001. in
  Array.iter
    (fun ((id, values), seconds) ->
      List.iter
        (fun (name, value) -> Printf.printf "%s\t%s\t%s\n" id name value)
        values;
      Printf.printf "%s\tlatency\t%.17g\n" id seconds)
    results;
  Printf.printf "STATS\t%.17g\t%.17g\t%.17g\t%d\t%d\t%.17g\n" elapsed cpu
    (a1 +. c1 -. b1 -. a0 -. c0 +. b0)
    (gc1.minor_collections - gc0.minor_collections)
    (gc1.major_collections - gc0.major_collections)
    clock_probe
