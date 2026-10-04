open Morphiq_risk
module F = Batch.Fast

let get = function Ok x -> x | Error _ -> failwith "test admission"
let check yes message = if not yes then failwith message
let same a b = Marshal.to_string a [] = Marshal.to_string b []
let lognormal = get (Vol.lognormal 0.2)
let normal = get (Vol.normal 2.)

let () =
  let bsm : Black.Bsm.inputs =
    {
      spot = 100.;
      strike = 95.;
      time_to_expiry = 1.;
      rate = 0.02;
      dividend_yield = 0.01;
    }
  in
  let black76 : Black.Black76.inputs =
    { forward = 100.; strike = 105.; time_to_expiry = 0.; rate = 0.02 }
  in
  let displaced : Black.Displaced.inputs =
    {
      forward = -2.;
      strike = -1.;
      displacement = 5.;
      time_to_expiry = 1.;
      rate = 0.02;
    }
  in
  let bachelier : Bachelier.inputs =
    { forward = -2.; strike = -1.; time_to_expiry = 1.; rate = 0.02 }
  in
  let invalid =
    F.Price (Batch.Bsm, { bsm with spot = Float.nan }, Side.Call, lognormal)
  in
  let overflow =
    F.Price
      ( Batch.Bachelier,
        {
          bachelier with
          forward = Float.max_float;
          strike = -.Float.max_float;
          time_to_expiry = 0.;
        },
        Side.Call,
        normal )
  in
  let requests =
    [|
      F.Price (Batch.Bsm, bsm, Side.Call, lognormal);
      invalid;
      F.Price (Batch.Black76, black76, Side.Put, lognormal);
      overflow;
      F.Price (Batch.Displaced, displaced, Side.Put, lognormal);
      F.Price (Batch.Bachelier, bachelier, Side.Put, normal);
    |]
  in
  let expected =
    [|
      Ok (Black.Bsm.price (get (Black.Bsm.admit bsm)) Side.Call lognormal);
      (match Black.Bsm.admit { bsm with spot = Float.nan } with
      | Error e -> Error (F.Invalid_input e)
      | Ok _ -> failwith "invalid admitted");
      Ok 5.;
      Error F.Numerical_failure;
      Ok
        (Black.Displaced.price
           (get (Black.Displaced.admit displaced))
           Side.Put lognormal);
      Ok (Bachelier.price (get (Bachelier.admit bachelier)) Side.Put normal);
    |]
  in
  check (same (F.run requests) expected) "one-shot outcomes";
  let compiled = F.compile requests in
  check (F.length compiled = Array.length expected) "length";
  Array.fill requests 0 (Array.length requests) invalid;
  let first = F.execute compiled in
  check (same first expected) "frozen input, order and failures";
  Array.fill first 0 (Array.length first) (Error F.Numerical_failure);
  check (same (F.execute compiled) expected) "fresh output and reusable plan";
  let workers =
    Array.init 3 (fun _ ->
        Domain.spawn (fun () ->
            for _ = 1 to 10 do
              check
                (same (F.execute compiled) expected)
                "concurrent immutable replay"
            done))
  in
  Array.iter Domain.join workers;
  check
    (F.length (F.compile [||]) = 0
    && F.run [||] = [||]
    && F.execute (F.compile [||]) = [||])
    "empty batch";
  print_endline
    "fast batch: mixed outcomes, finite guard, ownership and concurrent replay \
     pass"
