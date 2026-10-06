open Morphiq_risk
module A = Early_exercise.Bsm
module P = A.Piecewise

let get = function Ok x -> x | Error _ -> failwith "constructor"
let vol x = get (Vol.lognormal x)
let check name ok = if not ok then failwith name

let hex x =
  Marshal.to_string x [ Marshal.No_sharing ]
  |> String.to_seq
  |> Seq.map (fun c -> Printf.sprintf "%02x" (Char.code c))
  |> List.of_seq |> String.concat ""

let configuration scale =
  get
    (A.configure ~tolerance:(Float.ldexp scale (-30)) ~space_cells:128
       ~time_steps:128 ~domain_expansions:3
       ~limits:
         A.
           {
             max_nodes = 8192;
             max_steps = 131072;
             max_policy_solves = 1048576;
             max_row_visits = 1000000000;
             max_workspace_bytes = 8388608;
             policy_iterations = 64;
           })

let controls () =
  let p =
    A.
      {
        spot = 120.;
        strike = 100.;
        rate = 0.03;
        dividend_yield = 0.01;
        volatility = vol 0.2;
        time_to_expiry = 1.;
        opens_at = 1.;
      }
  in
  let cfg =
    get
      (A.configure ~tolerance:10. ~space_cells:32 ~time_steps:32
         ~domain_expansions:3
         ~limits:
           A.
             {
               max_nodes = 8192;
               max_steps = 131072;
               max_policy_solves = 1048576;
               max_row_visits = 1000000000;
               max_workspace_bytes = 8388608;
               policy_iterations = 64;
             })
  in
  let spec =
    A.
      {
        valuation_side = Regular;
        opening_side = After_cash;
        expiry_side = After_cash;
        dividends = [| { time = 1.; amount = 40. } |];
      }
  in
  let original = get (A.admit_cash p spec) in
  let not_reduced label p spec side =
    match A.price cfg (get (A.admit_cash p spec)) side with
    | Ok value ->
        check label (value.method_name <> "terminal-cash-European-reduction")
    | Error _ -> ()
  in
  not_reduced "earlier exercise guard" { p with opens_at = 0. }
    { spec with opening_side = Regular }
    Side.Call;
  not_reduced "earlier cash guard" p
    {
      spec with
      opening_side = Regular;
      expiry_side = Regular;
      dividends = [| { time = 0.5; amount = 40. } |];
    }
    Side.Call;
  not_reduced "cash put remains own payoff" p spec Side.Put;
  check "cancel before shortcut"
    (A.price ~cancel:(fun () -> true) cfg original Side.Call = Error A.Cancelled);
  let calls = ref 0 in
  check "cancel after event preparation"
    (A.price
       ~cancel:(fun () ->
         incr calls;
         !calls = 3)
       cfg original Side.Call
    = Error A.Cancelled);
  let marker = Failure "terminal cash caller marker" in
  check "caller exception preserved"
    (try
       ignore (A.price ~cancel:(fun () -> raise marker) cfg original Side.Call);
       false
     with e -> e == marker);
  let small =
    get
      (A.configure ~tolerance:10. ~space_cells:32 ~time_steps:32
         ~domain_expansions:3
         ~limits:
           A.
             {
               max_nodes = 8192;
               max_steps = 131072;
               max_policy_solves = 1048576;
               max_row_visits = 1;
               max_workspace_bytes = 8388608;
               policy_iterations = 64;
             })
  in
  let joint =
    get
      (A.admit_cash p
         {
           spec with
           dividends =
             [| { time = 1.; amount = 20. }; { time = 1.; amount = 20. } |];
         })
  in
  check "event preparation work cannot be skipped"
    (match A.price small joint Side.Call with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let requests =
    get (A.configure_greeks [ get (A.request_greek ~tolerance:100. A.Delta) ])
  in
  let greek = get (A.greeks cfg requests original Side.Call) in
  check "Greek route remains independently qualified"
    (greek.price.method_name <> "terminal-cash-European-reduction");
  print_endline "terminal cash controls passed"

let () =
  controls ();
  let baseline = Array.length Sys.argv = 3 && Sys.argv.(2) = "--baseline" in
  let ch = open_in Sys.argv.(1) in
  let count = ref 0 in
  (try
     while true do
       match String.split_on_char ' ' (input_line ch) with
       | [ id; phase; kind; s; k; r; q; v; cash; lower; upper ] ->
           let s = float_of_string s
           and k = float_of_string k
           and r = float_of_string r
           and q = float_of_string q
           and v = float_of_string v in
           let amounts =
             String.split_on_char ',' cash |> List.map float_of_string
           in
           let opening =
             if phase = "after" then A.After_cash else A.Before_cash
           in
           let expiry =
             if phase = "before" then A.Before_cash else A.After_cash
           in
           let spec =
             A.
               {
                 valuation_side = Regular;
                 opening_side = opening;
                 expiry_side = expiry;
                 dividends =
                   Array.of_list
                     (List.map (fun amount -> A.{ time = 1.; amount }) amounts);
               }
           in
           let dates =
             if opening = expiry then [| A.{ time = 1.; side = opening } |]
             else
               [|
                 A.{ time = 1.; side = opening }; A.{ time = 1.; side = expiry };
               |]
           in
           let cfg =
             configuration (List.fold_left Float.max (Float.max s k) amounts)
           in
           List.iter
             (fun bermudan ->
               let result =
                 if kind = "piecewise" then
                   let p =
                     P.
                       {
                         spot = s;
                         strike = k;
                         rate =
                           get
                             (P.Rate.create ~horizon:1. ~initial:r
                                ~changes:[| (0.5, -0.02) |]);
                         dividend_yield =
                           get
                             (P.Yield.create ~horizon:1. ~initial:q
                                ~changes:[| (0.25, 0.04) |]);
                         volatility =
                           get
                             (P.Volatility.create ~horizon:1. ~initial:(vol v)
                                ~changes:[| (0.75, vol 0.35) |]);
                         time_to_expiry = 1.;
                         opens_at = 1.;
                       }
                   in
                   P.price cfg
                     (get
                        (if bermudan then P.admit_bermudan ~cash:spec p dates
                         else P.admit_cash p spec))
                     Side.Call
                 else
                   let p =
                     A.
                       {
                         spot = s;
                         strike = k;
                         rate = r;
                         dividend_yield = q;
                         volatility = vol v;
                         time_to_expiry = 1.;
                         opens_at = 1.;
                       }
                   in
                   A.price cfg
                     (get
                        (if bermudan then A.admit_bermudan ~cash:spec p dates
                         else A.admit_cash p spec))
                     Side.Call
               in
               Printf.printf "ROW %s %b %s\n" id bermudan (hex result);
               (match result with
               | Error _ ->
                   if not baseline then
                     failwith (id ^ " terminal reduction refused")
               | Ok price ->
                   let value = Q.of_float price.value
                   and lo = Q.of_string lower
                   and hi = Q.of_string upper in
                   let err = Q.of_float price.maximum_roundoff_indicator in
                   Printf.printf "PRICE %s %b %h %h %s\n" id bermudan
                     price.value price.maximum_roundoff_indicator
                     price.method_name;
                   if not baseline then (
                     check
                       (id ^ " exact-reference containment")
                       (Q.compare (Q.sub value err) lo <= 0
                       && Q.compare (Q.add value err) hi >= 0);
                     check (id ^ " target")
                       (price.maximum_roundoff_indicator
                       <= price.requested_tolerance /. 64.);
                     check (id ^ " no grid or PDE")
                       (price.refinement = None && price.mapping = None
                      && price.work.steps = 0
                       && price.work.policy_solves = 0);
                     check
                       (id ^ " estimate assurance")
                       (price.assurance = A.Estimated_only)));
               incr count)
             [ false; true ]
       | _ -> failwith "malformed reference"
     done
   with End_of_file -> close_in ch);
  check "complete corpus" (!count = 80);
  Printf.printf "TOTAL %d\n" !count
