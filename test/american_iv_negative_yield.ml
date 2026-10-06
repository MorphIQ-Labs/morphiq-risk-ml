open Morphiq_risk
module A = Early_exercise.Bsm
module I = A.Implied_volatility

let get = function Ok x -> x | Error _ -> failwith "negative-yield refusal"
let vol x = get (Vol.lognormal x)

let () =
  let pricing =
    get
      (A.configure ~tolerance:1. ~space_cells:32 ~time_steps:32
         ~domain_expansions:2
         ~limits:
           A.
             {
               max_nodes = 8192;
               max_steps = 64 * 131072;
               max_policy_solves = 64 * 1048576;
               max_row_visits = 64 * 1000000000;
               max_workspace_bytes = 8388608;
               policy_iterations = 64;
             })
  in
  let cfg =
    get
      (I.configure ~pricing ~lower:(vol 0.05) ~upper:(vol 0.6) ~width:0.005
         ~max_evaluations:64)
  in
  let channel = open_in Sys.argv.(1) in
  let count = ref 0 in
  (try
     while true do
       match String.split_on_char ' ' (input_line channel) with
       | [ side; r; q; quote; lower; upper ] ->
           let side =
             if side = "call" then Side.Call
             else if side = "put" then Side.Put
             else failwith "side"
           in
           let p =
             A.
               {
                 spot = 100.;
                 strike = 100.;
                 rate = float_of_string r;
                 dividend_yield = float_of_string q;
                 time_to_expiry = 1.;
                 opens_at = 1.;
                 volatility = vol 0.77;
               }
           in
           List.iter
             (fun bermudan ->
               let admitted =
                 get
                   (if bermudan then
                      A.admit_bermudan p [| A.{ time = 1.; side = Regular } |]
                    else A.admit p)
               in
               let got =
                 get
                   (I.solve cfg admitted side
                      (get (I.quote (float_of_string quote))))
               in
               let lo = Q.of_float (Vol.to_float got.lower.volatility)
               and hi = Q.of_float (Vol.to_float got.upper.volatility) in
               if
                 Q.compare lo (Q.of_string lower) > 0
                 || Q.compare hi (Q.of_string upper) < 0
                 || Q.compare (Q.sub hi lo) (Q.of_float 0.005) > 0
               then failwith "independent negative-yield containment";
               Printf.printf "negative-yield %b %h %h %h %h\n" bermudan p.rate
                 p.dividend_yield
                 (Vol.to_float got.lower.volatility)
                 (Vol.to_float got.upper.volatility))
             [ false; true ];
           incr count
       | _ -> failwith "malformed negative-yield reference"
     done
   with End_of_file -> close_in channel);
  if !count <> 2 then failwith "incomplete negative-yield reference";
  print_endline
    "2 independent negative-yield quotes, 4 exercise-contract checks passed"
