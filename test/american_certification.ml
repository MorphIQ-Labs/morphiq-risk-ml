open Morphiq_risk
module A = Early_exercise.Bsm
module C = A.Certified

let get = function
  | Ok x -> x
  | Error _ -> failwith "unexpected constructor refusal"

let expect label b = if not b then failwith label
let limit x = get (C.absolute_error_limit x)

let model s k r q sigma t opens =
  A.
    {
      spot = s;
      strike = k;
      rate = r;
      dividend_yield = q;
      volatility = get (Vol.lognormal sigma);
      time_to_expiry = t;
      opens_at = opens;
    }

let admit kind p =
  let dates =
    if p.A.opens_at = p.time_to_expiry then
      [| A.{ time = p.time_to_expiry; side = Regular } |]
    else
      [|
        A.{ time = p.opens_at; side = Regular };
        A.{ time = p.time_to_expiry; side = Regular };
      |]
  in
  let cash =
    A.
      {
        valuation_side = Regular;
        opening_side = Regular;
        expiry_side = Regular;
        dividends =
          (if kind = "empty_cash" then [||]
           else
             [|
               { time = 0.5; amount = (if kind = "zero_cash" then 0. else 5.) };
             |]);
      }
  in
  get
    (match kind with
    | "american" -> A.admit p
    | "bermudan" -> A.admit_bermudan p dates
    | "cash" | "zero_cash" | "empty_cash" -> A.admit_cash p cash
    | "bermudan_cash" -> A.admit_bermudan ~cash p dates
    | _ -> failwith "unknown reference exercise style")

let controls () =
  List.iter
    (fun x ->
      expect "invalid accuracy"
        (C.absolute_error_limit x = Error C.Invalid_accuracy))
    [ nan; infinity; neg_infinity; -1.; -.Float.next_after 0. infinity ];
  ignore (limit (-0.));
  let unsupported = admit "american" (model 100. 100. 0.05 0. 0.2 1. 0.) in
  expect "large limit does not bypass capability"
    (C.price unsupported Side.Put ~max_error:(limit Float.max_float)
    = Error (C.Unsupported_capability C.General_stopping));
  let a = admit "american" (model 100. 100. 0. 0. 0.2 1. 0.) in
  expect "zero error on inexact price"
    (C.price a Side.Call ~max_error:(limit 0.) = Error C.Accuracy_exceeded);
  let zero = admit "american" (model 100. 100. 0. 0. 0.2 0. 0.) in
  expect "exact zero certificate"
    ((get (C.price zero Side.Call ~max_error:(limit 0.))).absolute_error = 0.);
  List.iter
    (fun stop ->
      let calls = ref 0 in
      let got =
        C.price
          ~cancel:(fun () ->
            incr calls;
            !calls = stop)
          a Side.Call ~max_error:(limit 1.)
      in
      expect "cancellation checkpoint" (got = Error C.Cancelled && !calls = stop))
    [ 1; 2 ];
  let marker = Failure "caller callback" in
  let propagated =
    try
      ignore
        (C.price
           ~cancel:(fun () -> raise marker)
           a Side.Call ~max_error:(limit 1.));
      false
    with e -> e == marker
  in
  expect "callback exception propagation" propagated

let () =
  controls ();
  let channel = open_in Sys.argv.(1) in
  let rows = ref 0
  and certified = ref 0
  and unsupported = ref 0
  and arithmetic = ref 0 in
  (try
     while true do
       let line = input_line channel in
       match String.split_on_char ' ' line with
       | [
        id;
        kind;
        side;
        s;
        k;
        r;
        q;
        sigma;
        t;
        opens;
        budget;
        expected;
        lower;
        upper;
       ] -> (
           incr rows;
           let f = float_of_string in
           let side = if side = "call" then Side.Call else Side.Put in
           let p = model (f s) (f k) (f r) (f q) (f sigma) (f t) (f opens) in
           let a = admit kind p in
           let result = C.price a side ~max_error:(limit (f budget)) in
           match (expected, result) with
           | "ok", Ok price ->
               incr certified;
               expect
                 (id ^ " finite certificate")
                 (Float.is_finite price.value
                 && Float.is_finite price.absolute_error
                 && price.absolute_error >= 0.
                 && price.absolute_error <= f budget);
               let got = Q.of_float price.value
               and radius = Q.of_float price.absolute_error in
               expect
                 (id ^ " independent interval containment")
                 (Q.compare (Q.sub got radius) (Q.of_string lower) <= 0
                 && Q.compare (Q.add got radius) (Q.of_string upper) >= 0);
               let basis =
                 if p.time_to_expiry = 0. then C.Expiry
                 else if p.opens_at = p.time_to_expiry then C.Terminal_only
                 else C.No_early_exercise_call
               in
               expect (id ^ " reduction identity") (price.reduction = basis);
               expect
                 (id ^ " exact acceptance limit")
                 (C.price a side ~max_error:(limit price.absolute_error)
                 = Ok price);
               if price.absolute_error > 0. then
                 expect
                   (id ^ " next tighter limit")
                   (C.price a side
                      ~max_error:(limit (Float.pred price.absolute_error))
                   = Error C.Accuracy_exceeded);
               Printf.printf "%s certified %h %h\n" id price.value
                 price.absolute_error
           | "unsupported", Error (C.Unsupported_capability C.General_stopping)
           | ( "cash_unsupported",
               Error (C.Unsupported_capability C.Cash_specification) ) ->
               incr unsupported;
               Printf.printf "%s %s\n" id expected
           | "arithmetic", Error C.Arithmetic_unresolved ->
               incr arithmetic;
               Printf.printf "%s arithmetic\n" id
           | _, got ->
               let actual =
                 match got with
                 | Ok v ->
                     Printf.sprintf "certificate value=%h bound=%h" v.value
                       v.absolute_error
                 | Error C.Arithmetic_unresolved -> "arithmetic unresolved"
                 | Error C.Accuracy_exceeded -> "accuracy exceeded"
                 | Error C.Invalid_accuracy -> "invalid accuracy"
                 | Error C.Cancelled -> "cancelled"
                 | Error (C.Unsupported_capability _) -> "unsupported"
               in
               failwith (id ^ " expected " ^ expected ^ ", got " ^ actual))
       | _ -> failwith "malformed certification reference row"
     done
   with End_of_file -> close_in channel);
  expect "complete reference corpus"
    (!rows = 354 && !certified = 337 && !unsupported = 16 && !arithmetic = 1);
  Printf.printf
    "American reductions: %d certificates, %d unsupported, %d unresolved \
     arithmetic\n"
    !certified !unsupported !arithmetic
