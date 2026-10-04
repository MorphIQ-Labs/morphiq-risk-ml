open Morphiq_risk

let get = function Ok value -> value | Error _ -> failwith "admission"
let check condition message = if not condition then failwith message
let f = Int64.float_of_bits

let () =
  (* Independent Arb cells are retained with original words in the #76 fixture.
     These controls also give named numerical mutants a direct witness. *)
  List.iter
    (fun scale ->
      List.iter
        (fun time ->
          let a =
            get
              (Black.Bsm.admit
                 {
                   spot = Float.ldexp (f 0x3ff0000000000001L) scale;
                   strike = Float.ldexp 1. scale;
                   time_to_expiry = time;
                   rate = f 0xbcafffffffffffffL /. time;
                   dividend_yield = 0.;
                 })
          in
          let got = Black.Bsm.price a Side.Call (get (Vol.lognormal 0.)) in
          check
            (got = Float.ldexp (f 0x3615555555555556L) scale)
            "cancelled zero-volatility price";
          check
            (Black.Bsm.price a Side.Put (get (Vol.lognormal 0.)) = 0.)
            "cancelled OTM payoff")
        [ 0.0625; 1.; 16. ])
    [ -400; 0; 400 ];
  let a =
    get
      (Black.Bsm.admit
         {
           spot = f 0x3ff0000000000001L;
           strike = 1.;
           time_to_expiry = 1.;
           rate = f 0xbcafffffffffffffL;
           dividend_yield = 0.;
         })
  in
  let got = Black.Bsm.price a Side.Call (get (Vol.lognormal 0x1p-160)) in
  (* Availability may improve; an uncertified expansion centre may not escape. *)
  check
    (Float.is_nan got || got = f 0x3615555555e74264L)
    "unresolved cell served an inaccurate finite value";
  Printf.printf
    "carry cancellation: exact-input values and unresolved-cell control passed\n"
