open Morphiq_risk
module I = Internal.Iv_iteration

let require label condition = if not condition then failwith label
let get = function Ok x -> x | Error e -> failwith (Refusal.to_string e)

let () =
  let square x = x *. x in
  let solve ?max_iterations proposal =
    I.solve ?max_iterations ~value:square ~proposal ~target:2.0 ~lower:0.0
      ~upper:2.0 ~initial:1.0 ()
  in
  require "iteration exhaustion is not a root"
    (solve ~max_iterations:0 (fun x _ -> x) = Error I.Non_convergence);
  List.iter
    (fun proposal ->
      match solve proposal with
      | Ok root ->
          require "safeguarded square-root inverse"
            (Float.abs (root -. Float.sqrt 2.0) <= Float.succ root -. root)
      | Error _ -> failwith "bisection fallback did not converge")
    [ (fun x _ -> x); (fun _ _ -> Float.nan); (fun _ _ -> Float.infinity) ];
  require "nonfinite evaluator is failure"
    (I.solve
       ~value:(fun _ -> Float.nan)
       ~proposal:(fun _ _ -> 1.0)
       ~target:1.0 ~lower:0.0 ~upper:2.0 ~initial:1.0 ()
    = Error I.Numerical_failure);
  require "unbracketed target is failure"
    (I.solve ~value:Fun.id
       ~proposal:(fun _ _ -> 1.0)
       ~target:3.0 ~lower:0.0 ~upper:2.0 ~initial:1.0 ()
    = Error I.Numerical_failure);
  require "nonfinite interior evaluation cannot manufacture a root"
    (I.solve
       ~value:(fun x -> if x = 0.0 || x = 2.0 then x else Float.nan)
       ~proposal:(fun _ _ -> 1.0)
       ~target:1.0 ~lower:0.0 ~upper:2.0 ~initial:1.0 ()
    = Error I.Numerical_failure);
  List.iter
    (fun target ->
      require "full exponent-range bracket terminates"
        (I.solve ~value:Fun.id
           ~proposal:(fun x _ -> x)
           ~target ~lower:0.0 ~upper:Float.max_float ~initial:1.0 ()
        = Ok target))
    [ 0x1p-1074; Float.min_float; 0.3; 0x1p1023 ];
  let bachelier =
    get
      (Bachelier.admit
         {
           forward = Float.max_float;
           strike = -.Float.max_float;
           time_to_expiry = 1.0;
           rate = 0.0;
         })
  in
  require "overflowed displacement is not Above_maximum or Root"
    (Bachelier.implied bachelier Side.Put 1.0 = Ok Iv.Numerical_failure);
  let bsm =
    get
      (Black.Bsm.admit
         {
           spot = 1.0;
           strike = 1.0;
           time_to_expiry = Float.max_float;
           rate = -.Float.max_float;
           dividend_yield = 0.0;
         })
  in
  require "nonfinite Black legs are not a mathematical classification"
    (Black.Bsm.implied bsm Side.Call 1.0 = Ok Iv.Numerical_failure);
  let normal =
    get
      (Bachelier.admit
         { forward = 0.0; strike = 0.0; time_to_expiry = 1.0; rate = 0.0 })
  in
  (match Bachelier.implied normal Side.Call 1.0 with
  | Ok (Iv.Root v) ->
      let root = Vol.to_float v in
      require "ATM normal inverse agrees with sqrt(2 pi)"
        (Float.abs (root -. 2.5066282746310005024)
        <= 2.0 *. (Float.succ root -. root))
  | _ -> failwith "ATM normal inverse unresolved");
  print_endline
    "IV termination, failed proposals, exponent range and arithmetic failures \
     passed"
