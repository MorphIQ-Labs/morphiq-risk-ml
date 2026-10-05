open Morphiq_risk
module A = Early_exercise.Bsm

let unwrap = function
  | Ok v -> v
  | Error _ -> failwith "unexpected constructor refusal"

let model ?(s = 100.) ?(k = 100.) ?(r = 0.05) ?(q = 0.02) ?(vol = 0.2) ?(t = 1.)
    ?(opens = 0.) () =
  A.
    {
      spot = s;
      strike = k;
      rate = r;
      dividend_yield = q;
      volatility = unwrap (Vol.lognormal vol);
      time_to_expiry = t;
      opens_at = opens;
    }

let spec ?(valuation = A.Regular) ?(opening = A.Regular) ?(expiry = A.Regular)
    dividends =
  A.
    {
      valuation_side = valuation;
      opening_side = opening;
      expiry_side = expiry;
      dividends =
        Array.of_list
          (List.map (fun (time, amount) -> { time; amount }) dividends);
    }

let limits =
  A.
    {
      max_nodes = 4096;
      max_steps = 32768;
      max_policy_solves = 262144;
      max_row_visits = 200000000;
      max_workspace_bytes = 4194304;
      policy_iterations = 64;
    }

let config ?(lim = limits) ?(cells = 32) ?(steps = 32) tolerance =
  unwrap
    (A.configure ~tolerance ~space_cells:cells ~time_steps:steps
       ~domain_expansions:2 ~limits:lim)

let failure = function
  | A.Resource_limit s -> "resource:" ^ s
  | A.Cancelled -> "cancelled"
  | A.Arithmetic_unresolved s -> "arithmetic:" ^ s
  | A.Unrepresentable -> "unrepresentable"
  | A.Nonconvergence { step; row; residual } ->
      Printf.sprintf "nonconvergence:%d:%d:%h" step row residual
  | A.Accuracy_not_demonstrated d ->
      let a, b = Option.value ~default:(0., 0.) d.event_changes in
      Printf.sprintf
        "accuracy:space=%h,%h:time=%h,%h:event=%h,%h:domain=%h,%h:spread=%h"
        (fst d.space_changes) (snd d.space_changes) (fst d.time_changes)
        (snd d.time_changes) a b (fst d.domain_changes) (snd d.domain_changes)
        d.boundary_half_spread

let good ?(cfg = config 1.) p c side =
  match A.price cfg (unwrap (A.admit_cash p c)) side with
  | Ok x -> x
  | Error e -> failwith (failure e)

let expect name b = if not b then failwith name

let controls () =
  let p = model ~s:105. ~r:0. ~q:0. ~t:0. () in
  let both =
    spec ~valuation:A.Before_cash ~opening:A.Before_cash ~expiry:A.After_cash
      [ (0., 10.) ]
  in
  let after = { both with opening_side = A.After_cash } in
  expect "pre-event call exercise" ((good p both Side.Call).value = 5.);
  expect "post-only call cannot exercise before jump"
    ((good p after Side.Call).value = 0.);
  expect "post-event put exercise" ((good p both Side.Put).value = 5.);
  let already = { after with valuation_side = A.After_cash } in
  expect "after valuation must not pay twice"
    ((good p already Side.Call).value = 5.);
  let before = { both with expiry_side = A.Before_cash } in
  expect "expiry before cash" ((good p before Side.Put).value = 0.);
  List.iter
    (fun c ->
      expect "invalid event metadata" (Result.is_error (A.admit_cash p c)))
    [
      { both with valuation_side = A.Regular };
      { after with expiry_side = A.Before_cash };
      spec [ (0., 10.) ];
      spec [ (0., nan) ];
      spec [ (-1., 1.) ];
      spec [ (1., 1.) ];
    ];
  List.iter
    (fun ds ->
      expect "invalid schedule"
        (Result.is_error (A.admit_cash (model ()) (spec ds))))
    [ [ (0.75, 1.); (0.5, 2.) ]; [ (0.5, -1.) ]; [ (0.5, infinity) ] ];
  expect "all inputs validated at expiry"
    (Result.is_error (A.admit_cash { p with rate = nan } both));
  let frozen = unwrap (A.admit_cash p both) in
  both.dividends.(0) <- A.{ time = 0.; amount = 90. };
  (Option.get (A.cash_specification frozen)).dividends.(0) <-
    A.{ time = 0.; amount = 80. };
  expect "schedule freeze and getter copy"
    ((unwrap (A.price (config 1.) frozen Side.Put)).value = 5.);
  let deterministic = model ~s:10. ~k:10. ~r:0. ~q:0. ~vol:0. () in
  expect "joint liquidator clamps stock at zero"
    ((good deterministic (spec [ (0.5, 7.); (0.5, 8.) ]) Side.Put).value = 10.);
  let original_sum =
    (good
       (model ~s:1. ~k:1. ~r:0. ~q:0. ~vol:0. ())
       (spec [ (0.5, 0.1); (0.5, 0.2) ])
       Side.Put)
      .value
  in
  expect "original-word joint sum rounds once" (original_sum = 0.1 +. 0.2);
  let interior =
    good
      (model ~s:100. ~k:90. ~r:0.25 ~q:0.125 ~t:8. ~vol:0. ())
      (spec [ (6., 5.) ])
      Side.Call
  in
  expect "stationary stop before cash"
    (abs_float (interior.value -. (250. /. 9.)) < 1e-12);
  let empty = spec [] in
  let ordinary = unwrap (A.admit (model ~s:50. ())) in
  expect "empty schedule preserves value"
    ((good (model ~s:50. ()) empty Side.Put).value
   = (unwrap (A.price (config 1.) ordinary Side.Put)).value);
  let zero = good (model ~s:50. ()) (spec [ (0.5, 0.) ]) Side.Put in
  expect "zero payment reduction" (zero.value = 50.);
  expect "event identity retained"
    (match zero.mapping with Some m -> m.event_applications > 0 | _ -> false);
  let cp = unwrap (A.admit_cash (model ~s:50. ()) (spec [ (0.5, 5.) ])) in
  let detailed =
    unwrap
      (A.price ~premium:true ~exercise_regions:true (config 1.) cp Side.Put)
  in
  expect "no mismatched European premium"
    (match detailed.early_exercise_premium with
    | A.Unavailable _ -> true
    | _ -> false);
  expect "mapping refinement recorded"
    (match detailed.refinement with
    | Some { event_changes = Some _; _ } -> true
    | _ -> false);
  expect "cancellation before cash allocation"
    (A.price ~cancel:(fun () -> true) (config 1.) cp Side.Put
    = Error A.Cancelled);
  let calls = ref 0 in
  expect "cancellation during cash work"
    (A.price
       ~cancel:(fun () ->
         incr calls;
         !calls = 20)
       (config 1.) cp Side.Put
    = Error A.Cancelled);
  expect "cash metadata cap"
    (match
       A.price
         (config ~lim:{ limits with max_row_visits = 1 } 1.)
         (unwrap (A.admit_cash deterministic (spec [ (0.25, 1.); (0.5, 1.) ])))
         Side.Put
     with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let huge =
    unwrap
      (A.admit_cash deterministic
         (spec [ (0.5, Float.max_float); (0.5, Float.max_float) ]))
  in
  expect "unrepresentable joint total fails numerically"
    (Result.is_error (A.price (config 1.) huge Side.Put));
  let task = Domain.spawn (fun () -> A.price (config 1.) cp Side.Put) in
  expect "cash call-owned scratch"
    (Domain.join task = A.price (config 1.) cp Side.Put);
  let at_zero =
    good
      (model ~s:10. ~r:0. ~q:0. ())
      (spec ~valuation:A.Before_cash ~opening:A.After_cash [ (0., 20.) ])
      Side.Put
  in
  expect "stochastic jump to absorbing zero" (at_zero.value = 100.);
  let coarse =
    A.price (config 1.)
      (unwrap (A.admit_cash (model ()) (spec [ (0.5, 5.) ])))
      Side.Call
  in
  expect "mapping must refine independently"
    (match coarse with
    | Error (A.Accuracy_not_demonstrated { event_changes = Some (a, b); _ }) ->
        max a b > 0.125
    | _ -> false);
  print_endline "American cash controls passed"

let decode s = Int64.float_of_bits (Int64.of_string ("0x" ^ s))

let phase = function
  | "0" -> A.Regular
  | "1" -> A.Before_cash
  | "2" -> A.After_cash
  | _ -> failwith "phase"

let corpus path refined =
  let lim, cells, steps =
    if refined then
      ( {
          limits with
          max_nodes = 8192;
          max_steps = 131072;
          max_policy_solves = 1048576;
          max_row_visits = 1000000000;
          max_workspace_bytes = 8388608;
        },
        128,
        128 )
    else (limits, 32, 32)
  in
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      try
        while true do
          match String.split_on_char ' ' (input_line ic) with
          | id :: side :: s :: k :: r :: q :: vol :: t :: opens :: epsilon
            :: valuation :: opening :: expiry :: count :: ds -> (
              let rec dividends = function
                | [] -> []
                | time :: amount :: tail ->
                    (decode time, decode amount) :: dividends tail
                | _ -> failwith "truncated cash"
              in
              let ds = dividends ds in
              if List.length ds <> int_of_string count then
                failwith "cash count";
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
              let cash =
                spec ~valuation:(phase valuation) ~opening:(phase opening)
                  ~expiry:(phase expiry) ds
              in
              let cfg = config ~lim ~cells ~steps (decode epsilon) in
              match A.price cfg (unwrap (A.admit_cash p cash)) side with
              | Error e ->
                  Printf.printf "%s\tunavailable\t-\t%s\n%!" id (failure e)
              | Ok x ->
                  Printf.printf
                    "%s\testimated\t%h\t%s:steps=%d:rows=%d:map=%d:roundoff=%h\n\
                     %!"
                    id x.value x.method_name x.work.steps x.work.row_visits
                    (Option.fold ~none:0
                       ~some:(fun m -> m.A.event_applications)
                       x.mapping)
                    x.maximum_roundoff_indicator)
          | _ -> failwith "cash protocol"
        done
      with End_of_file -> ())

let bench mode =
  let p = model () in
  let admitted =
    match mode with
    | "none" -> unwrap (A.admit p)
    | "zero" -> unwrap (A.admit_cash p (spec [ (0.5, 0.) ]))
    | "cash" -> unwrap (A.admit_cash p (spec [ (0.5, 5.) ]))
    | _ -> failwith "benchmark mode"
  in
  let cfg =
    config ~cells:128 ~steps:128
      ~lim:
        {
          limits with
          max_nodes = 8192;
          max_steps = 131072;
          max_policy_solves = 1048576;
          max_row_visits = 1000000000;
          max_workspace_bytes = 8388608;
        }
      1.
  in
  let run () =
    match A.price cfg admitted Side.Put with
    | Ok _ -> ()
    | Error e -> failwith (failure e)
  in
  run ();
  Gc.full_major ();
  let bytes = Gc.allocated_bytes () and start = Unix.gettimeofday () in
  for _ = 1 to 3 do
    run ()
  done;
  Printf.printf
    "{\"mode\":%S,\"iterations\":3,\"seconds_per_request\":%.17g,\"allocated_bytes_per_request\":%.17g}\n"
    mode
    ((Unix.gettimeofday () -. start) /. 3.)
    ((Gc.allocated_bytes () -. bytes) /. 3.)

let () =
  match Array.to_list Sys.argv with
  | [ _ ] -> controls ()
  | [ _; "--corpus"; path ] | [ _; "--"; path ] -> corpus path false
  | [ _; "--refined-corpus"; path ] -> corpus path true
  | [ _; "--bench"; mode ] -> bench mode
  | [ _; "--help" ] ->
      print_endline
        "american_cash [--corpus FILE|--refined-corpus FILE|--bench \
         none/zero/cash|-- FILE|--version]"
  | [ _; "--version" ] -> print_endline "american-cash 1"
  | _ ->
      prerr_endline "unknown arguments";
      exit 2
