open Morphiq_risk
module A = Early_exercise.Bsm

let get = function Ok x -> x | Error _ -> failwith "work-order admission"

let run budget stop side =
  let limits =
    A.
      {
        max_nodes = 512;
        max_steps = 32768;
        max_policy_solves = 262144;
        max_row_visits = budget;
        max_workspace_bytes = 2097152;
        policy_iterations = 64;
      }
  in
  let cfg =
    get
      (A.configure ~tolerance:10. ~space_cells:16 ~time_steps:16
         ~domain_expansions:2 ~limits)
  in
  let p =
    get
      (A.admit
         A.
           {
             spot = 100.;
             strike = 100.;
             rate = 0.0625;
             dividend_yield = 0.03125;
             opens_at = 0.;
             time_to_expiry = 1.;
             volatility = get (Vol.lognormal 0.25);
           })
  in
  let calls = ref 0 in
  let result =
    A.price
      ~cancel:(fun () ->
        incr calls;
        !calls = stop)
      cfg p side
  in
  if stop > 0 && !calls = stop && result <> Error A.Cancelled then
    failwith "cancel precedence";
  Printf.printf "%d\t%d\t%d\t%S\n" budget stop !calls
    (Marshal.to_string result [ Marshal.No_sharing ])

let () =
  List.iter
    (fun side ->
      List.iter
        (fun budget -> run budget 0 side)
        [
          1;
          255;
          256;
          257;
          511;
          512;
          513;
          1023;
          1024;
          1025;
          4095;
          4096;
          4097;
          16383;
          16384;
          16385;
          10000000;
        ];
      List.iter
        (fun stop -> run 10000000 stop side)
        [ 1; 2; 3; 4; 7; 12; 31; 64; 127; 256 ])
    [ Side.Call; Side.Put ]
