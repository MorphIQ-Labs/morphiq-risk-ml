open Morphiq_risk
module A = Early_exercise.Bsm

let unwrap = function
  | Ok v -> v
  | Error _ -> failwith "unexpected constructor refusal"

let sigma x = unwrap (Vol.lognormal x)

let model ?(s = 100.) ?(k = 100.) ?(r = 0.05) ?(q = 0.02) ?(t = 1.)
    ?(opens = 0.) ?(vol = 0.2) () =
  A.
    {
      spot = s;
      strike = k;
      rate = r;
      dividend_yield = q;
      time_to_expiry = t;
      opens_at = opens;
      volatility = sigma vol;
    }

let limits =
  A.
    {
      max_nodes = 4096;
      max_steps = 4096;
      max_policy_solves = 32768;
      max_row_visits = 50000000;
      max_workspace_bytes = 4194304;
      policy_iterations = 32;
    }

let config ?(limits = limits) ?(cells = 32) ?(steps = 32) tolerance =
  unwrap
    (A.configure ~tolerance ~space_cells:cells ~time_steps:steps
       ~domain_expansions:2 ~limits)

let failure = function
  | A.Resource_limit s -> "resource:" ^ s
  | A.Cancelled -> "cancelled"
  | A.Arithmetic_unresolved s -> "arithmetic:" ^ s
  | A.Unrepresentable -> "unrepresentable"
  | A.Nonconvergence { step; row; residual } ->
      Printf.sprintf "nonconvergence:%d:%d:%h" step row residual
  | A.Accuracy_not_demonstrated d ->
      Printf.sprintf "accuracy:space=%h,%h:time=%h,%h:domain=%h,%h:spread=%h"
        (fst d.space_changes) (snd d.space_changes) (fst d.time_changes)
        (snd d.time_changes) (fst d.domain_changes) (snd d.domain_changes)
        d.boundary_half_spread

let expect name predicate = if not predicate then failwith name

let good config p side =
  match A.price config (unwrap (A.admit p)) side with
  | Ok v -> v
  | Error e -> failwith (failure e)

let controls () =
  let cfg = config 1. in
  List.iter
    (fun p ->
      expect "full admission before expiry" (Result.is_error (A.admit p)))
    [
      model ~r:nan ~t:0. ();
      model ~s:(-1.) ();
      model ~opens:2. ();
      model ~q:infinity ();
    ];
  let expired = good cfg (model ~s:105. ~t:0. ()) Side.Call in
  expect "expiry payoff" (expired.value = 5. && expired.refinement = None);
  let interior =
    good cfg (model ~s:100. ~k:90. ~r:0.25 ~q:0.125 ~vol:0. ~t:8. ()) Side.Call
  in
  expect "interior stopping" (abs_float (interior.value -. (250. /. 9.)) < 1e-12);
  let absorbing = good cfg (model ~s:0. ~r:(-0.125) ~t:2. ()) Side.Put in
  expect "negative rate absorbing put exceeds strike" (absorbing.value > 100.);
  let zero_strike = good cfg (model ~k:0. ~q:(-0.125) ~t:2. ()) Side.Call in
  expect "negative yield call exceeds spot" (zero_strike.value > 100.);
  let calls = ref 0 in
  let cancelled =
    A.price
      ~cancel:(fun () ->
        incr calls;
        !calls = 1)
      cfg
      (unwrap (A.admit (model ())))
      Side.Put
  in
  expect "cancel before allocation" (cancelled = Error A.Cancelled);
  let before_return =
    A.price
      ~cancel:(fun () ->
        incr calls;
        !calls >= 3)
      cfg
      (unwrap (A.admit (model ~t:0. ())))
      Side.Put
  in
  expect "cancel before publishing analytical success"
    (before_return = Error A.Cancelled);
  let count = ref 0 in
  let during =
    A.price
      ~cancel:(fun () ->
        incr count;
        !count = 12)
      cfg
      (unwrap (A.admit (model ())))
      Side.Put
  in
  expect "cancel during numerical work" (during = Error A.Cancelled);
  List.iter
    (fun (name, lim) ->
      let result =
        A.price (config ~limits:lim 1.) (unwrap (A.admit (model ()))) Side.Put
      in
      expect name
        (match result with Error (A.Resource_limit _) -> true | _ -> false))
    [
      ("node cap", { limits with max_nodes = 8 });
      ("byte cap", { limits with max_workspace_bytes = 64 });
      ("step cap", { limits with max_steps = 1 });
      ("policy cap", { limits with max_policy_solves = 1 });
      ("row cap", { limits with max_row_visits = 1 });
    ];
  let unresolved =
    A.price
      (config ~limits:{ limits with max_steps = max_int } 0x1p-16)
      (unwrap (A.admit (model ())))
      Side.Put
  in
  expect "excessive W cannot loosen roundoff screen"
    (match unresolved with
    | Error (A.Arithmetic_unresolved _) -> true
    | _ -> false);
  let nonconvergence =
    A.price
      (config ~limits:{ limits with policy_iterations = 1 } 1.)
      (unwrap (A.admit (model ())))
      Side.Put
  in
  expect "policy cap is not a last-iterate price"
    (match nonconvergence with
    | Error (A.Nonconvergence { residual; _ }) ->
        Float.is_finite residual && residual > 0.
    | _ -> false);
  let vanishing =
    A.price cfg
      (unwrap (A.admit (model ~vol:(Float.next_after 0. infinity) ())))
      Side.Put
  in
  expect "positive volatility underflow is not deterministic"
    (match vanishing with
    | Error (A.Arithmetic_unresolved _) -> true
    | _ -> false);
  let deep = unwrap (A.admit (model ~s:50. ())) in
  let detailed =
    match A.price ~exercise_regions:true ~premium:true cfg deep Side.Put with
    | Ok v -> v
    | Error e -> failwith (failure e)
  in
  expect "deep put exercises" (detailed.value = 50.);
  expect "regions own availability"
    (match detailed.exercise_regions with
    | A.Available (_ :: _) -> true
    | _ -> false);
  expect "matching premium"
    (match detailed.early_exercise_premium with
    | A.Available p ->
        p.value > 0. && p.european_value < 50.
        && p.european_absolute_error >= 0.
    | _ -> false);
  let delayed = good cfg (model ~s:50. ~opens:0.5 ()) Side.Put in
  expect "no exercise before opening"
    (delayed.value < 50. && delayed.value > 45.);
  let scale e =
    good
      (config (Float.ldexp 1. e))
      (model ~s:(Float.ldexp 50. e) ~k:(Float.ldexp 100. e) ())
      Side.Put
  in
  List.iter
    (fun e ->
      expect "currency scaling" ((scale e).value = Float.ldexp detailed.value e))
    [ -20; 20 ];
  let task = Domain.spawn (fun () -> A.price cfg deep Side.Put) in
  let local = A.price cfg deep Side.Put in
  expect "call-owned scratch" (Domain.join task = local);
  let callback_raised =
    try
      ignore (A.price ~cancel:(fun () -> raise Exit) cfg deep Side.Put);
      false
    with Exit -> true
  in
  expect "caller exception propagates" callback_raised;
  Printf.printf "American public controls passed\n%!"

let decode s = Int64.float_of_bits (Int64.of_string ("0x" ^ s))

let corpus path refined =
  let lim, cells, steps =
    if refined then
      ( {
          limits with
          max_nodes = 8192;
          max_steps = 32768;
          max_policy_solves = 262144;
          max_row_visits = 400000000;
          max_workspace_bytes = 8388608;
        },
        128,
        256 )
    else (limits, 32, 32)
  in
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      try
        while true do
          let fields = String.split_on_char ' ' (input_line ic) in
          match fields with
          | [ id; side; s; k; r; q; vol; t; opens; epsilon ] -> (
              let side =
                match side with
                | "call" -> Side.Call
                | "put" -> Side.Put
                | _ -> failwith "side"
              in
              let p =
                model ~s:(decode s) ~k:(decode k) ~r:(decode r) ~q:(decode q)
                  ~vol:(decode vol) ~t:(decode t) ~opens:(decode opens) ()
              in
              let cfg = config ~limits:lim ~cells ~steps (decode epsilon) in
              match A.price cfg (unwrap (A.admit p)) side with
              | Error e ->
                  Printf.printf "%s\tunavailable\t-\t%s\n%!" id (failure e)
              | Ok v ->
                  Printf.printf
                    "%s\testimated\t%h\t%s:steps=%d:policies=%d:rows=%d:roundoff=%h:grid=%d:upper=%h:time=%d:domains=%d:switched=%d\n\
                     %!"
                    id v.value v.method_name v.work.steps v.work.policy_solves
                    v.work.row_visits v.maximum_roundoff_indicator
                    v.work.final_nodes v.work.final_upper_stock
                    v.work.finest_steps_per_slab v.work.domain_expansions
                    v.work.switched_rows)
          | _ -> failwith "input protocol"
        done
      with End_of_file -> ())

let bench mode =
  let p = model () in
  let admitted = unwrap (A.admit p) in
  let cfg =
    config ~cells:128 ~steps:256
      ~limits:
        {
          limits with
          max_nodes = 8192;
          max_steps = 32768;
          max_policy_solves = 262144;
          max_row_visits = 400000000;
          max_workspace_bytes = 8388608;
        }
      1.
  in
  let operation () =
    match mode with
    | "admission" ->
        ignore (Sys.opaque_identity (A.admit (Sys.opaque_identity p)))
    | "price" | "diagnostics" -> (
        let result =
          A.price ~exercise_regions:(mode = "diagnostics")
            ~premium:(mode = "diagnostics") cfg admitted Side.Put
        in
        match Sys.opaque_identity result with
        | Ok _ -> ()
        | Error e -> failwith (failure e))
    | _ -> failwith "unknown benchmark mode"
  in
  operation ();
  Gc.full_major ();
  let count = if mode = "admission" then 100000 else 3 in
  let allocated = Gc.allocated_bytes () and start = Unix.gettimeofday () in
  for _ = 1 to count do
    operation ()
  done;
  let elapsed = Unix.gettimeofday () -. start in
  let bytes = Gc.allocated_bytes () -. allocated in
  Printf.printf
    "{\"mode\":%S,\"iterations\":%d,\"seconds_per_request\":%.17g,\"allocated_bytes_per_request\":%.17g}\n\
     %!"
    mode count
    (elapsed /. float count)
    (bytes /. float count)

let () =
  match Array.to_list Sys.argv with
  | [ _ ] -> controls ()
  | [ _; "--corpus"; path ] | [ _; "--"; path ] -> corpus path false
  | [ _; "--bench"; mode ] -> bench mode
  | [ _; "--refined-corpus"; path ] -> corpus path true
  | [ _; ("--help" | "-h") ] ->
      print_endline
        "american_pricing [--corpus FILE|--refined-corpus FILE|--bench \
         admission/price/diagnostics|-- FILE|--version]"
  | [ _; "--version" ] -> print_endline "american-pricing-campaign-v1"
  | _ ->
      prerr_endline "unknown arguments";
      exit 2
