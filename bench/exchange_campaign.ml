open Morphiq_risk

let float word = Int64.float_of_bits (Int64.of_string ("0x" ^ word))

let result words =
  match List.map float words with
  | [ s1; s2; q1; q2; sigma1; sigma2; rho; time; limit ] -> (
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
          | Error _ -> "invalid_input"
          | Ok a -> (
              match Exchange.price a ~max_error:limit with
              | Ok c -> Printf.sprintf "served %h %h" c.value c.absolute_error
              | Error Exchange.Invalid_accuracy -> "invalid_accuracy"
              | Error Exchange.Numerical_failure -> "numerical_failure"
              | Error Exchange.Accuracy_exceeded -> "accuracy_exceeded"))
      | _ -> "invalid_input")
  | _ -> failwith "expected nine original words"

let () =
  if Array.length Sys.argv <> 1 then (
    prerr_endline "Read case ID and nine hex words per line from stdin";
    exit 2);
  try
    while true do
      match String.split_on_char ' ' (read_line ()) with
      | id :: words -> Printf.printf "%s %s\n%!" id (result words)
      | [] -> failwith "empty request"
    done
  with End_of_file -> ()
