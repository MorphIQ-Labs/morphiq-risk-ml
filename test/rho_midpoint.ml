open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "admission"
let f = Int64.float_of_bits

let () =
  (* With S=K and zero rates, positive sigma makes Phi(d2)<1/2 strictly.
     Odd K*T/minsub products are halfway points: calls round down and puts
     round away from zero. No rounded CDF may erase that strict inequality. *)
  List.iter
    (fun k ->
      let a =
        get
          (Black.Bsm.admit
             {
               spot = k;
               strike = k;
               time_to_expiry = 0x1p-1074;
               rate = 0.;
               dividend_yield = 0.;
             })
      in
      let n = int_of_float k in
      List.iter
        (fun (side, expected) ->
          let g = Black.Bsm.greeks a side (get (Vol.lognormal 0.25)) in
          match g.rho with
          | Ok v when v = expected -> ()
          | _ -> failwith "rho lost the side of a subnormal midpoint")
        [
          (Side.Call, f (Int64.of_int (n / 2)));
          (Side.Put, -.f (Int64.of_int ((n + 1) / 2)));
        ])
    [ 1.; 3.; 5.; 7. ];
  let tail =
    get
      (Black.Bsm.admit
         {
           spot = 1.;
           strike = 100.;
           time_to_expiry = 1.;
           rate = 0.;
           dividend_yield = 0.;
         })
  in
  let g = Black.Bsm.greeks tail Side.Call (get (Vol.lognormal 0.05)) in
  (match g.rho with
  | Ok 0. -> ()
  | _ -> failwith "proved tail zero lost availability");
  let tail2 =
    get
      (Black.Bsm.admit
         {
           spot = 1.;
           strike = 2.;
           time_to_expiry = 1.;
           rate = 0.;
           dividend_yield = 0.;
         })
  in
  let g = Black.Bsm.greeks tail2 Side.Call (get (Vol.lognormal 0.015)) in
  (match g.rho with
  | Ok 0. -> ()
  | _ -> failwith "full tail zero proof lost availability");
  List.iter
    (fun (side, spot, rate, q, expected) ->
      let a =
        get
          (Black.Bsm.admit
             {
               spot = f spot;
               strike = 100.;
               time_to_expiry = f 0x3f66719f3601671aL;
               rate;
               dividend_yield = q;
             })
      in
      let g = Black.Bsm.greeks a side (get (Vol.lognormal 0.05)) in
      match g.rho with
      | Ok value when value = f expected -> ()
      | _ -> failwith "existing independently resolved subnormal tail rho lost")
    [
      (Side.Call, 0x40569ef5a02e89c5L, 0.02, 0.02, 0x13d5L);
      (Side.Call, 0x40569ef5a02e89c5L, 0.05, 0.01, 0x6241L);
      (Side.Put, 0x405ba118083ca14bL, 0.02, 0.02, 0x80000000000015ecL);
      (Side.Put, 0x405ba118083ca14bL, 0.05, 0.01, 0x800000000000046bL);
    ];
  print_endline "rho midpoint: independently strict call/put rounding cells"
