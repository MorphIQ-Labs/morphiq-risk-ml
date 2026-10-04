open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "invalid example input"

let () =
  let receive =
    Exchange.
      {
        spot = 100.;
        dividend_yield = 0.01;
        volatility = get (Vol.lognormal 0.2);
      }
  and deliver =
    Exchange.
      {
        spot = 95.;
        dividend_yield = 0.02;
        volatility = get (Vol.lognormal 0.3);
      }
  in
  let admitted =
    get
      (Exchange.admit ~receive ~deliver ~time_to_expiry:1.
         ~correlation:(get (Exchange.correlation 0.5)))
  in
  match Exchange.price admitted ~max_error:1e-9 with
  | Ok { value; absolute_error } ->
      Printf.printf
        "Exchange price %.12g; absolute error <= %.6g currency units\n" value
        absolute_error
  | Error Exchange.Invalid_accuracy -> failwith "invalid absolute-error limit"
  | Error Exchange.Accuracy_exceeded ->
      failwith "requested accuracy unavailable"
  | Error Exchange.Numerical_failure ->
      failwith "numerical enclosure unresolved"
