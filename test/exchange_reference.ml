open Morphiq_risk

let fail id message = failwith (id ^ ": " ^ message)
let float word = Int64.float_of_bits (Int64.of_string ("0x" ^ word))

let get = function
  | Ok x -> x
  | Error _ -> failwith "unexpected admission failure"

let evaluate s1 s2 q1 q2 sigma1 sigma2 rho time limit =
  match
    (Vol.lognormal sigma1, Vol.lognormal sigma2, Exchange.correlation rho)
  with
  | Ok v1, Ok v2, Ok correlation -> (
      let receive =
        Exchange.{ spot = s1; dividend_yield = q1; volatility = v1 }
      in
      let deliver =
        Exchange.{ spot = s2; dividend_yield = q2; volatility = v2 }
      in
      match
        Exchange.admit ~receive ~deliver ~time_to_expiry:time ~correlation
      with
      | Error _ -> `Invalid
      | Ok a -> `Price (Exchange.price a ~max_error:limit))
  | _ -> `Invalid

let () =
  let channel = open_in Sys.argv.(1) in
  let rows = ref 0
  and served = ref 0
  and failed = ref 0
  and unadjudicated = ref 0 in
  (try
     while true do
       let line = input_line channel in
       match String.split_on_char ' ' line with
       | id :: required :: status :: s1 :: s2 :: q1 :: q2 :: sigma1 :: sigma2
         :: rho :: time :: limit :: bounds -> (
           incr rows;
           let limit = float limit in
           let result =
             evaluate (float s1) (float s2) (float q1) (float q2) (float sigma1)
               (float sigma2) (float rho) (float time) limit
           in
           let required = required = "1" in
           match result with
           | `Invalid ->
               if status <> "invalid_input" then
                 fail id "unexpected invalid input";
               Printf.printf "%s invalid_input\n" id
           | `Price (Error Exchange.Invalid_accuracy) ->
               if status <> "invalid_accuracy" then
                 fail id "unexpected invalid accuracy";
               Printf.printf "%s invalid_accuracy\n" id
           | `Price (Error error) ->
               incr failed;
               if required then fail id "mandatory certificate unavailable";
               if status <> "interval" && status <> "unresolved" then
                 fail id "wrong invalid outcome";
               Printf.printf "%s %s\n" id
                 (match error with
                 | Exchange.Numerical_failure -> "numerical_failure"
                 | Exchange.Accuracy_exceeded -> "accuracy_exceeded"
                 | Exchange.Invalid_accuracy -> assert false)
           | `Price (Ok cert) ->
               incr served;
               if status <> "interval" && status <> "unresolved" then
                 fail id "served invalid input";
               if
                 not
                   (Float.is_finite cert.value && cert.value >= 0.
                   && Float.is_finite cert.absolute_error
                   && cert.absolute_error >= 0.
                   && cert.absolute_error <= limit)
               then fail id "invalid certificate";
               let centre = Q.of_float cert.value
               and radius = Q.of_float cert.absolute_error in
               (match bounds with
               | [ low1; high1; low2; high2 ] ->
                   List.iter
                     (fun word ->
                       if
                         Q.compare
                           (Q.abs (Q.sub centre (Q.of_string word)))
                           radius
                         > 0
                       then fail id "independent interval outside certificate")
                     [ low1; high1; low2; high2 ]
               | [] when status = "unresolved" && not required ->
                   incr unadjudicated
               | _ -> fail id "missing reference bounds");
               Printf.printf "%s %s %h %h\n" id
                 (if status = "unresolved" then "unadjudicated" else "served")
                 cert.value cert.absolute_error)
       | _ -> failwith "malformed exchange fixture"
     done
   with End_of_file -> close_in channel);
  if !rows <> 66 then failwith "exchange membership changed";
  (* Typed correlation must still reject invalid original words at expiry. *)
  List.iter
    (fun rho ->
      match Exchange.correlation rho with
      | Error Exchange.Invalid_correlation -> ()
      | _ -> failwith "invalid correlation accepted")
    [ nan; infinity; Float.succ 1.; Float.pred (-1.) ];
  let v = get (Vol.lognormal 0.2) in
  let receive = Exchange.{ spot = 100.; dividend_yield = 0.; volatility = v } in
  let deliver =
    Exchange.{ spot = 95.; dividend_yield = infinity; volatility = v }
  in
  (match
     Exchange.admit ~receive ~deliver ~time_to_expiry:0.
       ~correlation:(get (Exchange.correlation 0.))
   with
  | Error (Exchange.Invalid_asset (Exchange.Deliver, Exchange.Dividend_yield))
    ->
      ()
  | _ -> failwith "expiry bypassed leg admission");
  Printf.printf
    "exchange: %d rows, %d certificates, %d explicit numerical/accuracy \
     failures, %d served but reference unresolved\n"
    !rows !served !failed !unadjudicated
