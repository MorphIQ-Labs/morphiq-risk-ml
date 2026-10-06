open Morphiq_risk
module I = Backend_inputs
module K = Internal.American_policy
module A = Early_exercise.Bsm

let get = I.get

let () =
  let n = 514 in
  let b =
    Array.init 9 (fun k ->
        Array.init n (fun _ ->
            if k = 1 || k = 6 then 2.
            else if k = 0 || k = 2 then -0.25
            else if k = 8 then 42.
            else 1.))
  in
  let s =
    K.create ~lo:b.(0) ~diag:b.(1) ~hi:b.(2) ~rhs:b.(3) ~values:b.(4)
      ~payoff:b.(5) ~pivots:b.(6) ~solution_rhs:b.(7) ~candidate:b.(8)
      ~mask:(Array.make n false) ~oldmask:(Array.make n false)
  in
  K.reset s ~obstacle:false;
  let code = K.run s K.Eliminate ~first:2 ~last:2 in
  let changed =
    Array.fold_left (fun c x -> if x <> 42. then c + 1 else c) 0 b.(8)
  in
  Printf.printf "BLOCK\t%d\t%d\t%d\n%!" code (K.visited s) changed;
  let a =
    get
      (A.admit
         A.
           {
             spot = 100.;
             strike = 100.;
             rate = 0.05;
             dividend_yield = 0.02;
             volatility = get (Vol.lognormal 0.2);
             time_to_expiry = 1.;
             opens_at = 0.;
           })
  in
  List.iter
    (fun stop ->
      let calls = ref 0 in
      let result =
        A.price
          ~cancel:(fun () ->
            incr calls;
            !calls >= stop)
          I.cfg a Side.Put
      in
      Printf.printf "CANCEL\t%d\t%d\t%s\n%!" stop !calls (I.digest result))
    [ 1; 2; 8; 32; 128; 512; 1024 ];
  List.iter
    (fun visits ->
      let cfg =
        get
          (A.configure ~tolerance:1. ~space_cells:64 ~time_steps:64
             ~domain_expansions:2
             ~limits:
               A.
                 {
                   max_nodes = 8192;
                   max_steps = 131072;
                   max_policy_solves = 1048576;
                   max_row_visits = visits;
                   max_workspace_bytes = 8388608;
                   policy_iterations = 64;
                 })
      in
      let result = A.price cfg a Side.Put in
      Printf.printf "BUDGET\t%d\t%s\n%!" visits (I.digest result))
    [ 500; 2000; 10000 ]
