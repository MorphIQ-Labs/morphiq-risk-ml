open Morphiq_risk
module P = Internal.Bachelier_fast
module N = Internal.Bachelier_native
module F = Batch.Fast

external raw : int -> float array -> float array -> unit
  = "morphiq_bachelier_kernel"

let get = function Ok x -> x | Error _ -> failwith "admission"
let check b why = if not b then failwith why
let same a b = Marshal.to_string a [] = Marshal.to_string b []
let vol = get (Vol.normal 1.)

let request i =
  F.Price
    ( Batch.Bachelier,
      {
        forward = -.(0.5 +. (float (i mod 32) /. 16.));
        strike = 0.;
        time_to_expiry = 1.;
        rate = 0.;
      },
      Side.Call,
      vol )

let prepared i =
  let a =
    get
      (Bachelier.admit
         {
           forward = -.(0.5 +. (float (i mod 32) /. 16.));
           strike = 0.;
           time_to_expiry = 1.;
           rate = 0.;
         })
  in
  match P.prepare a Side.Call vol with
  | Some p -> p
  | None -> failwith "selection"

let () =
  List.iter
    (fun n ->
      let inputs = Array.init n prepared in
      let expected = Array.map P.price inputs in
      let plan = N.compile inputs in
      check (N.length plan = n) "native length";
      if n > 0 then inputs.(0) <- prepared 15;
      List.iter
        (fun scalar ->
          let out = N.execute ~scalar plan in
          check (same out expected) "native replay, odd tail and frozen storage";
          if n > 0 then out.(0) <- Float.nan;
          check (same (N.execute ~scalar plan) expected) "native output alias";
          let workers =
            Array.init 3 (fun _ ->
                Domain.spawn (fun () ->
                    for _ = 1 to 10 do
                      check
                        (same (N.execute ~scalar plan) expected)
                        "native concurrent replay"
                    done))
          in
          Array.iter Domain.join workers)
        [ true; false ])
    [ 0; 1; 2; 3; 31; 32; 33; 256 ];
  List.iter
    (fun n ->
      let inputs = Array.init n request in
      if n > 2 then
        inputs.(2) <-
          F.Price
            ( Batch.Bachelier,
              {
                forward = Float.nan;
                strike = 0.;
                time_to_expiry = 1.;
                rate = 0.;
              },
              Side.Call,
              vol );
      if n > 3 then
        inputs.(3) <-
          F.Price
            ( Batch.Bachelier,
              { forward = 1.; strike = 0.; time_to_expiry = 0.; rate = 0. },
              Side.Call,
              vol );
      let expected = F.run inputs in
      let batch = F.compile inputs in
      check (F.length batch = n) "batch length";
      if n > 0 then inputs.(0) <- request 15;
      check
        (same (F.execute batch) expected)
        "batch native/fallback order and frozen input";
      let output = F.execute batch in
      if n > 0 then output.(0) <- Error F.Numerical_failure;
      check (same (F.execute batch) expected) "batch output ownership";
      let d = Domain.spawn (fun () -> F.execute batch) in
      check (same (F.execute batch) (Domain.join d)) "batch concurrent replay")
    [ 0; 1; 31; 32; 33; 64; 65; 256 ];
  let rejects f =
    match f () with
    | () -> failwith "native guard accepted malformed call"
    | exception Invalid_argument _ -> ()
  in
  List.iter
    (fun mode -> rejects (fun () -> raw mode [||] [||]))
    [ 0; 3; max_int; min_int ];
  rejects (fun () -> raw 1 [| 1. |] [| 1.; 2. |]);
  rejects (fun () -> raw 2 [||] [| 1. |]);
  Printf.printf
    "Native Bachelier backend %d: shape, scalar/SIMD, odd tails, ownership and \
     batch replay pass\n"
    N.backend
