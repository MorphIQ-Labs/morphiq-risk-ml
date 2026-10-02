open Morphiq_risk
module Dd = Internal.Dd

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)
let require label yes = if not yes then failwith label

let () =
  List.iter
    (fun e ->
      require "nonfinite error accepted"
        (not (Bounds.within ~error:e ~bound:1.0)))
    [ Float.nan; Float.infinity; Float.neg_infinity ];
  require "nonfinite bound accepted"
    (not (Bounds.within ~error:0.0 ~bound:Float.infinity));
  require "reference expansion loses cancellation"
    (Bounds.expansion_error [ 1.0; Bounds.u; -1.0; -.Bounds.u +. Bounds.u2 ]
    = Bounds.u2);
  (* An error expressed in price ULPs does not keep that ULP count after
     multiplication. This case turns 32 price ULPs into 61 rho ULPs. *)
  let p = ref 1.0 in
  for _ = 1 to 32 do
    p := Float.succ !p
  done;
  let got = 1.9 *. !p in
  let bound =
    Bounds.scaled_price_error ~time:1.9 ~price:!p ~got ~reference:1.9
      ~budget:32.0
  in
  require "rho propagation" (Bounds.within ~error:(got -. 1.9) ~bound);
  require "rho witness does not distinguish the old rule"
    (got -. 1.9 > 33.0 *. Bounds.ulp 1.9);
  (* Both the carry and the scaled intrinsic may be below binary64's range,
     while the price is normal. Exercise both sides and several scales. *)
  List.iter
    (fun exponent ->
      List.iter
        (fun rate ->
          List.iter
            (fun sign ->
              let s = Float.ldexp 1.0 exponent in
              let a =
                get
                  (Black.Bsm.admit
                     {
                       spot = s;
                       strike = s;
                       time_to_expiry = 0x1p-1074;
                       rate = sign *. rate;
                       dividend_yield = 0.0;
                     })
              in
              let side = if sign > 0.0 then Side.Call else Side.Put in
              let p = Black.Bsm.price a side (get (Vol.lognormal 0.0)) in
              let expected = Float.ldexp rate (exponent - 1074) in
              require "tiny carry lost before currency scaling" (p = expected))
            [ -1.0; 1.0 ])
        [ 0.25; 1.0; 4.0 ])
    [ 100; 500; 1000 ];
  let shifted =
    get
      (Black.Displaced.admit
         {
           forward = 0x1p-573;
           strike = 0x1p-574;
           displacement = 0x1p500;
           time_to_expiry = 1.0;
           rate = 0.0;
         })
  in
  require "tiny displaced intrinsic lost at normalized scale"
    (Black.Displaced.price shifted Side.Call (get (Vol.lognormal 0.0))
    = 0x1p-574);
  let rows = ref 0 in
  In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line "%s %Lx %Lx %d %Lx %Lx %Lx"
             (fun kind a b e h l tail ->
               incr rows;
               let f = Int64.float_of_bits in
               let a = f a
               and b = f b
               and h = f h
               and l = f l
               and tail = f tail in
               match kind with
               | "iv" ->
                   let contract =
                     get
                       (Black.Black76.admit
                          {
                            forward = 1.0;
                            strike = 1.0;
                            time_to_expiry = 1.0;
                            rate = a;
                          })
                   in
                   let root = Float.ldexp h e in
                   let got =
                     match get (Black.Black76.implied contract Side.Call b) with
                     | Iv.Root v -> Vol.to_float v
                     | _ -> failwith "near-maximum root lost"
                   in
                   let bound =
                     Iv_bounds.black_interval_bound "black76" ~side_call:true
                       ~s:1.0 ~k:1.0 ~t:1.0 ~r:a ~q:0.0 ~shift:0.0 ~quote:b
                       ~root ~candidate:got
                   in
                   require "near-maximum root exceeds propagated bound"
                     (Bounds.within ~error:(Float.abs (got -. root)) ~bound)
               | "coordinate" ->
                   let contract =
                     get
                       (Black.Bsm.admit
                          {
                            spot = a;
                            strike = b;
                            time_to_expiry = 1.0;
                            rate = 0.0;
                            dividend_yield = 0.0;
                          })
                   in
                   let x, xl =
                     match Black.Bsm.coordinates contract with
                     | Black.Coordinates.Live c -> (c.x, c.x_low)
                     | _ -> failwith "live coordinate missing"
                   in
                   let error =
                     Bounds.expansion_error
                       [
                         Float.ldexp x (-e);
                         -.h;
                         Float.ldexp xl (-e);
                         -.l;
                         -.tail;
                       ]
                   in
                   let log_q = Float.abs (Float.log (a /. b)) in
                   let absolute =
                     (Bounds.eps_log *. log_q)
                     +. (15.0 *. Bounds.u *. Bounds.u2)
                     +. (9.0 *. Bounds.u2 *. Float.abs (Float.ldexp h e))
                   in
                   require "double-word quotient remainder lost"
                     (Bounds.within ~error
                        ~bound:
                          (Float.ldexp absolute (-e)
                           *. (1.0 +. (8.0 *. Bounds.u))
                          +. 0x1p-158))
               | _ -> invalid_arg kind));
  require "empty regression corpus" (!rows > 0);
  Printf.printf "%d generated regressions and boundary controls passed\n" !rows
