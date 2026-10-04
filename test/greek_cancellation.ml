open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "admission"

let () =
  let admitted =
    get
      (Black.Bsm.admit
         {
           spot = Float.succ 1.;
           strike = 1.;
           time_to_expiry = 1.;
           rate = Int64.float_of_bits 0xbcafffffffffffffL;
           dividend_yield = 0.;
         })
  in
  let greeks =
    Black.Bsm.greeks admitted Side.Call (get (Vol.lognormal 0x1p-160))
  in
  (* Independently enclosed original-input Arb cells, retained in #80's fixture.
     A future refined value may restore availability; the damaged DD result may
     not escape as a successful finite derivative. *)
  List.iter
    (fun (name, word) ->
      match Greek_values.pick greeks name with
      | Error Greeks.Numerical_failure -> ()
      | Error Greeks.Payoff_kink ->
          failwith (name ^ ": smooth input called kink")
      | Ok value ->
          let budget = List.assoc ("black " ^ name) Budget_greeks.values in
          if Float_score.ulps value (Int64.float_of_bits word) > budget then
            failwith (name ^ ": inaccurate cancellation Greek"))
    [
      ("delta", 0x3fefffffe61da6afL);
      ("gamma", 0x4891d37def22940eL);
      ("theta", 0x3c26719f23d9e19fL);
      ("vega", 0x3e91d37def229410L);
      ("rho", 0x3fefffffe61da6b1L);
      ("vanna", 0xc8b7c4a7e9837013L);
      ("volga", 0x48dfb0dfe2049570L);
      ("charm", 0x44c901643417414fL);
      ("veta", 0xc4f0ab9822ba2b8aL);
      ("color", 0xcef0ab9822ba2b88L);
    ];
  let underflow =
    get
      (Black.Bsm.admit
         {
           spot = 1.;
           strike = 1.;
           time_to_expiry = 0x1p-1074;
           rate = 0x1p-1074;
           dividend_yield = 0.;
         })
  in
  let g = Black.Bsm.greeks underflow Side.Call (get (Vol.lognormal 0.)) in
  (* Exact positive real carry: delta is 1, never a payoff kink. *)
  (match g.delta with
  | Error Greeks.Numerical_failure | Ok 1. -> ()
  | _ -> failwith "underflowed carry became a kink or inaccurate delta");
  List.iter
    (fun (q, r, reference) ->
      let a =
        get
          (Black.Bsm.admit
             {
               spot = Float.succ 1.;
               strike = 1.;
               time_to_expiry = 1.;
               rate = Int64.float_of_bits r;
               dividend_yield = q;
             })
      in
      let g = Black.Bsm.greeks a Side.Put (get (Vol.lognormal 0.)) in
      match g.theta with
      | Error Greeks.Numerical_failure -> ()
      | Error Greeks.Payoff_kink -> failwith "off-ATM theta called kink"
      | Ok value ->
          if
            Float_score.ulps (value :> float) (Int64.float_of_bits reference)
            > 8.
          then failwith "zero-variance theta lost discount-leg difference")
    [
      (-0.125, 0xbfc0000000000008L, 0xbc296ea480a6dec3L);
      (0.125, 0x3fbffffffffffff0L, 0xbc23ce7e5905f7aeL);
    ];
  let shifted =
    get
      (Black.Displaced.admit
         {
           forward = Float.succ 1.;
           strike = 1.;
           displacement = 0x1p54;
           time_to_expiry = 1.;
           rate = 0.125;
         })
  in
  List.iter
    (fun (side, reference) ->
      let g =
        Black.Displaced.greeks shifted side (get (Vol.lognormal 0x1p-106))
      in
      match g.theta with
      | Error Greeks.Numerical_failure -> ()
      | Error Greeks.Payoff_kink -> failwith "smooth shifted theta called kink"
      | Ok value ->
          if
            Float_score.ulps (value :> float) (Int64.float_of_bits reference)
            > 8.
          then failwith "smooth theta lost discount-leg difference")
    [ (Side.Call, 0x3bc24a66a21e2e0fL); (Side.Put, 0xbbf1853184c231ebL) ];
  print_endline "Greek cancellation: original-input values or explicit failure"
