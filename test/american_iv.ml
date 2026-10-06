open Morphiq_risk
module A = Early_exercise.Bsm
module I = A.Implied_volatility

let get = function Ok x -> x | Error _ -> failwith "constructor"
let vol x = get (Vol.lognormal x)
let quote x = get (I.quote x)
let check label x = if not x then failwith label

let model ?(s = 100.) ?(k = 100.) ?(r = 0.05) ?(q = 0.) ?(t = 1.) ?(opens = 0.)
    () =
  A.
    {
      spot = s;
      strike = k;
      rate = r;
      dividend_yield = q;
      time_to_expiry = t;
      opens_at = opens;
      volatility = vol 0.77;
    }

let configuration ?(cells = 128) ?(tolerance = 1.) ?(workspace = 8388608)
    ?(expansions = 2) ?(parts = 64) () =
  get
    (A.configure ~tolerance ~space_cells:cells ~time_steps:cells
       ~domain_expansions:expansions
       ~limits:
         A.
           {
             max_nodes = 8192;
             max_steps = parts * 131072;
             max_policy_solves = parts * 1048576;
             max_row_visits = parts * 1000000000;
             max_workspace_bytes = workspace;
             policy_iterations = 64;
           })

let settings ?(evaluations = 64) ?(width = 0.05) ?(lower = 0.05) ?(upper = 0.6)
    cfg =
  get
    (I.configure ~pricing:cfg ~lower:(vol lower) ~upper:(vol upper) ~width
       ~max_evaluations:evaluations)

let outcome = function
  | Ok _ -> "interval"
  | Error I.Invalid_quote -> "invalid-quote"
  | Error (I.Invalid_configuration _) -> "invalid-configuration"
  | Error I.Unsupported_cash_put -> "unsupported-cash-put"
  | Error (I.No_solution _) -> "no-solution"
  | Error (I.Non_identifiable _) -> "non-identifiable"
  | Error (I.Estimated_outside_search_range I.Below) -> "below-range"
  | Error (I.Estimated_outside_search_range I.Above) -> "above-range"
  | Error I.Price_uncertainty_or_plateau -> "uncertainty-or-plateau"
  | Error I.Inconsistent_prices -> "inconsistent-prices"
  | Error (I.Pricing_failed (A.Resource_limit _)) -> "price-resource"
  | Error (I.Pricing_failed (A.Accuracy_not_demonstrated _)) -> "price-accuracy"
  | Error (I.Pricing_failed _) -> "price-failure"
  | Error I.Evaluation_limit -> "evaluation-limit"
  | Error I.Unrepresentable_progress -> "unrepresentable-progress"
  | Error I.Cancelled -> "cancelled"

let cash p amount =
  A.
    {
      valuation_side = Regular;
      opening_side = After_cash;
      expiry_side = After_cash;
      dividends = [| { time = p.A.time_to_expiry; amount } |];
    }

let controls () =
  let cfg = configuration ~cells:32 () in
  List.iter
    (fun x -> check "invalid quote" (I.quote x = Error I.Invalid_quote))
    [ nan; infinity; neg_infinity; -1. ];
  ignore (quote (-0.));
  List.iter
    (fun width ->
      check "invalid width"
        (Result.is_error
           (I.configure ~pricing:cfg ~lower:(vol 0.05) ~upper:(vol 0.6) ~width
              ~max_evaluations:64)))
    [ 0.; -1.; nan; infinity ];
  check "invalid order"
    (Result.is_error
       (I.configure ~pricing:cfg ~lower:(vol 0.6) ~upper:(vol 0.05) ~width:0.1
          ~max_evaluations:64));
  check "invalid evaluations"
    (Result.is_error
       (I.configure ~pricing:cfg ~lower:(vol 0.05) ~upper:(vol 0.6) ~width:0.1
          ~max_evaluations:1));
  let a = get (A.admit (model ())) in
  let solve ?(cfg = settings cfg) ?(a = a) side q =
    I.solve cfg a side (quote q)
  in
  check "bounded inverse exhaustion"
    (solve ~cfg:(settings ~evaluations:2 cfg) Side.Call 10.
    = Error I.Evaluation_limit);
  check "finite range is not global absence"
    (solve Side.Call 40. = Error (I.Estimated_outside_search_range I.Above));
  check "mathematical cap"
    (solve Side.Call 101. = Error (I.No_solution I.Above_global_cap));
  let expiry = get (A.admit (model ~t:0. ~s:101. ())) in
  check "expiry nonidentifiability"
    (solve ~a:expiry Side.Call 1. = Error (I.Non_identifiable I.Expiry));
  check "expiry incompatible quote"
    (match solve ~a:expiry Side.Call 2. with
    | Error (I.No_solution _) -> true
    | _ -> false);
  check "absorbing nonidentifiability"
    (solve ~a:(get (A.admit (model ~s:0. ()))) Side.Call 0.
    = Error (I.Non_identifiable I.Absorbing_stock));
  check "zero strike nonidentifiability"
    (solve ~a:(get (A.admit (model ~k:0. ()))) Side.Call 100.
    = Error (I.Non_identifiable I.Zero_strike));
  check "metadata budget"
    (outcome
       (solve ~cfg:(settings (configuration ~workspace:1 ())) Side.Call 10.)
    = "price-resource");
  let p = model ~opens:1. () in
  let with_cash = get (A.admit_cash p (cash p 10.)) in
  check "cash-put guard"
    (solve ~a:with_cash Side.Put 10. = Error I.Unsupported_cash_put);
  let empty =
    A.
      {
        valuation_side = Regular;
        opening_side = Regular;
        expiry_side = Regular;
        dividends = [||];
      }
  in
  check "empty cash-put guard"
    (solve ~a:(get (A.admit_cash p empty)) Side.Put 10.
    = Error I.Unsupported_cash_put);
  let plateau = get (A.admit (model ~s:0. ~k:0. ())) in
  check "plateau never root" (Result.is_error (solve ~a:plateau Side.Call 0.));
  List.iter
    (fun stop ->
      let count = ref 0 in
      let got =
        I.solve
          ~cancel:(fun () ->
            incr count;
            !count = stop)
          (settings cfg) a Side.Call (quote 10.)
      in
      check "cancellation" (got = Error I.Cancelled && !count = stop))
    [ 1; 2 ];
  let marker = Internal.Enclosure.Unresolved "caller-owned exception" in
  check "callback exceptions preserved"
    (try
       ignore
         (I.solve
            ~cancel:(fun () -> raise marker)
            (settings cfg) a Side.Call (quote 10.));
       false
     with e -> e == marker);
  let uncertain_cfg = configuration ~parts:2 ~cells:32 ~tolerance:100. () in
  let uncertain_model = model ~q:0.02 () in
  let observed =
    get
      (A.price
         (configuration ~parts:1 ~cells:32 ~tolerance:100. ())
         (get (A.admit { uncertain_model with volatility = vol 0.2 }))
         Side.Put)
  in
  let uncertain =
    I.solve
      (settings ~evaluations:2 ~lower:0.199 ~upper:0.201 ~width:0.01
         uncertain_cfg)
      (get (A.admit uncertain_model))
      Side.Put (quote observed.value)
  in
  check "empirical price uncertainty cannot collapse to a root"
    (uncertain = Error I.Price_uncertainty_or_plateau);
  let terminal = model ~opens:1. ~q:0.02 () in
  let terminal =
    get (A.admit_bermudan terminal [| A.{ time = 1.; side = Regular } |])
  in
  let interval =
    get
      (I.solve
         (settings ~evaluations:2 ~width:1. cfg)
         terminal Side.Put (quote 10.))
  in
  check "Bermudan rights preserved at both endpoints"
    (interval.lower.price.method_name = "European-reduction"
    && interval.upper.price.method_name = "European-reduction");
  let finite_dates =
    Array.map (fun time -> A.{ time; side = Regular }) [| 0.; 0.5; 1. |]
  in
  let finite = get (A.admit_bermudan (model ~q:0.02 ()) finite_dates) in
  let finite_interval =
    get
      (I.solve
         (settings ~evaluations:2 ~width:1.
            (configuration ~parts:2 ~cells:32 ~tolerance:100. ~expansions:3 ()))
         finite Side.Put (quote 10.))
  in
  check "finite rights must not become continuous exercise"
    (finite_interval.lower.price.method_name = "backward-Euler-Bermudan-v1"
    && finite_interval.upper.price.method_name = "backward-Euler-Bermudan-v1");
  let delayed =
    get (A.admit (model ~s:120. ~k:100. ~r:0. ~q:0.2 ~opens:1. ()))
  in
  check "delayed exercise has no immediate-payoff floor"
    (Result.is_ok (solve ~a:delayed Side.Call 5.));
  check "negative-rate cap is not strike"
    (solve ~a:(get (A.admit (model ~s:0. ~r:(-0.1) ()))) Side.Put 105.
    = Error (I.No_solution I.Incompatible_constant_price));
  let calls = ref 0 in
  check "cancel within PDE work"
    (I.solve
       ~cancel:(fun () ->
         incr calls;
         !calls = 10)
       (settings uncertain_cfg)
       (get (A.admit uncertain_model))
       Side.Put (quote 10.)
     = Error I.Cancelled
    && !calls = 10);
  let strict = settings (configuration ~cells:32 ~tolerance:1e-12 ()) in
  check "strict price failure is not a sign"
    (match
       I.solve strict (get (A.admit uncertain_model)) Side.Put (quote 10.)
     with
    | Error (I.Pricing_failed _) -> true
    | _ -> false);
  let p0 = model ~s:120. ~t:0. () in
  let at_event opening_side =
    get
      (A.admit_cash p0
         A.
           {
             valuation_side = Before_cash;
             opening_side;
             expiry_side = After_cash;
             dividends = [| { time = 0.; amount = 10. } |];
           })
  in
  check "expiry after cash preserves jump"
    (solve ~a:(at_event A.After_cash) Side.Call 10.
    = Error (I.Non_identifiable I.Expiry));
  check "expiry before cash retains immediate exercise"
    (solve ~a:(at_event A.Before_cash) Side.Call 20.
    = Error (I.Non_identifiable I.Expiry));
  print_endline "American inverse controls passed"

let hex x =
  let s = Marshal.to_string x [ Marshal.No_sharing ] in
  String.concat ""
    (List.init (String.length s) (fun i ->
         Printf.sprintf "%02x" (Char.code s.[i])))

let () =
  controls ();
  let all = Array.length Sys.argv > 2 && Sys.argv.(2) = "all" in
  let width =
    if Array.length Sys.argv > 3 then float_of_string Sys.argv.(3) else 0.05
  in
  let expansions =
    if Array.length Sys.argv > 4 then int_of_string Sys.argv.(4) else 2
  in
  let cfg = settings ~width (configuration ~expansions ()) in
  let channel = open_in Sys.argv.(1) in
  let rows = ref 0
  and accepted = ref 0
  and refused = ref 0
  and skipped = ref 0 in
  (try
     while true do
       let line = input_line channel in
       match String.split_on_char ' ' line with
       | [
        id; style; side; s; k; r; q; t; opens; amount; quote_word; lo; hi; route;
       ] ->
           incr rows;
           let f = float_of_string in
           if (not all) && (route = "discrete" || f amount <> 0.) then (
             incr skipped;
             Printf.printf "SKIP %s manual-refinement\n%!" id)
           else
             let p =
               model ~s:(f s) ~k:(f k) ~r:(f r) ~q:(f q) ~t:(f t)
                 ~opens:(f opens) ()
             in
             let cash =
               if f amount = 0. then None else Some (cash p (f amount))
             in
             let admitted =
               get
                 (if style = "bermudan" then
                    let times =
                      if p.opens_at = p.time_to_expiry then [ p.time_to_expiry ]
                      else
                        List.filter
                          (fun x -> x >= p.opens_at)
                          [ 0.; 0.25; 0.5; 0.75; 1. ]
                    in
                    let dates =
                      Array.of_list
                        (List.map
                           (fun time ->
                             A.
                               {
                                 time;
                                 side =
                                   (if Option.is_some cash then After_cash
                                    else Regular);
                               })
                           times)
                    in
                    A.admit_bermudan ?cash p dates
                  else
                    match cash with
                    | None -> A.admit p
                    | Some c -> A.admit_cash p c)
             in
             let side = if side = "call" then Side.Call else Side.Put in
             let result = I.solve cfg admitted side (quote (f quote_word)) in
             (match result with
             | Ok v ->
                 incr accepted;
                 let lower = Q.of_float (Vol.to_float v.lower.volatility)
                 and upper = Q.of_float (Vol.to_float v.upper.volatility) in
                 check
                   (id ^ " independent inverse containment")
                   (Q.compare lower (Q.of_string lo) <= 0
                   && Q.compare upper (Q.of_string hi) >= 0);
                 check
                   (id ^ " entire requested width")
                   (Q.compare (Q.sub upper lower) (Q.of_float width) <= 0);
                 check
                   (id ^ " lower price uncertainty")
                   (Q.compare
                      (Q.add
                         (Q.of_float v.lower.price.value)
                         (Q.of_float v.lower.uncertainty_indicator))
                      (Q.of_float (f quote_word))
                   < 0);
                 check
                   (id ^ " upper price uncertainty")
                   (Q.compare
                      (Q.sub
                         (Q.of_float v.upper.price.value)
                         (Q.of_float v.upper.uncertainty_indicator))
                      (Q.of_float (f quote_word))
                   > 0);
                 check "bounded evaluation count"
                   (v.evaluations >= 2 && v.evaluations <= 64);
                 Printf.printf "ROOT %s %h %h %d\n" id
                   (Vol.to_float v.lower.volatility)
                   (Vol.to_float v.upper.volatility)
                   v.evaluations
             | Error _ ->
                 incr refused;
                 if not all then failwith (id ^ " " ^ outcome result));
             Printf.printf "ROW %s %s %s\n%!" id (outcome result) (hex result)
       | _ -> failwith "malformed inverse reference"
     done
   with End_of_file -> close_in channel);
  check "complete reference corpus" (!rows = 30);
  Printf.printf "TOTAL %d %d %d %d\n%!" !rows !accepted !refused !skipped
