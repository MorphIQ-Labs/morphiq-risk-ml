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

let expect name b = if not b then failwith name

let dates xs =
  Array.of_list (List.map (fun (time, side) -> A.{ time; side }) xs)

let regular xs = dates (List.map (fun t -> (t, A.Regular)) xs)

let good ?(cfg = config 1.) ?cash p ds side =
  match A.price cfg (unwrap (A.admit_bermudan ?cash p ds)) side with
  | Ok x -> x
  | Error e -> failwith (failure e)

let controls () =
  let p = model ~opens:0.5 () in
  let ds = regular [ 0.5; 1. ] in
  let admitted = unwrap (A.admit_bermudan p ds) in
  ds.(0) <- A.{ time = 0.; side = Regular };
  let saved = Option.get (A.exercise_schedule admitted) in
  expect "copied admission" (saved.(0).time = 0.5);
  saved.(0) <- A.{ time = 0.; side = Regular };
  expect "copied getter"
    ((Option.get (A.exercise_schedule admitted)).(0).time = 0.5);
  expect "American identity" (A.exercise_schedule (unwrap (A.admit p)) = None);
  List.iter
    (fun ds ->
      expect "invalid rights" (Result.is_error (A.admit_bermudan p ds)))
    [
      regular [];
      regular [ 1.; 0.5 ];
      regular [ 0.5; 0.5; 1. ];
      regular [ 0.5 ];
      regular [ 0.; 1. ];
      regular [ 0.5; nan; 1. ];
      regular [ 0.5; infinity; 1. ];
      dates [ (0.5, A.Before_cash); (1., A.Regular) ];
    ];
  let deterministic = model ~s:100. ~k:90. ~r:0.25 ~q:0.125 ~vol:0. ~t:8. () in
  let sparse = (good deterministic (regular [ 0.; 8. ]) Side.Call).value in
  let middle = (good deterministic (regular [ 0.; 4.; 8. ]) Side.Call).value in
  let endpoint t = (100. *. exp (-0.125 *. t)) -. (90. *. exp (-0.25 *. t)) in
  expect "no unlisted stationary exercise"
    (abs_float (sparse -. max 10. (endpoint 8.)) < 1e-12);
  expect "listed middle exercise"
    (abs_float (middle -. endpoint 4.) < 1e-12 && middle > sparse);
  let cash = spec ~opening:A.After_cash [ (0.5, 20.) ] in
  let p = model ~k:90. ~r:0. ~q:0. ~vol:0. ~opens:0.5 () in
  let after = dates [ (0.5, A.After_cash); (1., A.Regular) ] in
  expect "no pre-cash right" ((good ~cash p after Side.Call).value = 0.);
  let cash = { cash with opening_side = A.Before_cash } in
  let both =
    dates [ (0.5, A.Before_cash); (0.5, A.After_cash); (1., A.Regular) ]
  in
  expect "pre-cash right" ((good ~cash p both Side.Call).value = 10.);
  expect "mismatched first side"
    (Result.is_error (A.admit_bermudan ~cash p after));
  expect "cash Regular rejected"
    (Result.is_error (A.admit_bermudan ~cash p (regular [ 0.5; 1. ])));
  let frozen = unwrap (A.admit_bermudan ~cash p both) in
  cash.dividends.(0) <- A.{ time = 0.5; amount = 0. };
  expect "cash array copied"
    ((Option.get (A.cash_specification frozen)).dividends.(0).amount = 20.);
  let p = model ~k:90. ~r:0. ~q:0. ~vol:0. ~opens:0.5 () in
  expect "unlisted cash date still maps stock"
    ((good ~cash:(spec [ (0.25, 20.) ]) p (regular [ 0.5; 1. ]) Side.Call).value
   = 0.);
  let p = model ~s:105. ~r:0. ~q:0. ~t:0. () in
  let cash =
    spec ~valuation:A.Before_cash ~opening:A.Before_cash ~expiry:A.After_cash
      [ (0., 10.) ]
  in
  let ds = dates [ (0., A.Before_cash); (0., A.After_cash) ] in
  expect "zero-time before call" ((good ~cash p ds Side.Call).value = 5.);
  expect "zero-time after put" ((good ~cash p ds Side.Put).value = 5.);
  expect "valuation cannot follow first right"
    (Result.is_error
       (A.admit_bermudan ~cash:{ cash with valuation_side = A.After_cash } p ds));
  let p = model ~s:0. ~k:100. ~r:0.05 ~opens:0.5 () in
  expect "absorbing first right"
    (abs_float
       ((good p (regular [ 0.5; 1. ]) Side.Put).value -. (100. *. exp (-0.025)))
    < 1e-12);
  let p = model ~s:0. ~k:100. ~r:(-0.05) ~opens:0.5 () in
  expect "absorbing last right"
    (abs_float
       ((good p (regular [ 0.5; 1. ]) Side.Put).value -. (100. *. exp 0.05))
    < 1e-12);
  let p = model ~opens:1. () in
  List.iter
    (fun side ->
      let b = good p (regular [ 1. ]) side in
      let a = unwrap (A.price (config 1.) (unwrap (A.admit p)) side) in
      expect "singleton European"
        (b.value = a.value && b.assurance = A.Estimated_only))
    [ Side.Call; Side.Put ];
  let cancelled =
    A.price ~cancel:(fun () -> true) (config 1.) admitted Side.Put
  in
  expect "cancelled" (cancelled = Error A.Cancelled);
  let raised =
    try
      ignore
        (A.price
           ~cancel:(fun () -> failwith "callback")
           (config 1.) admitted Side.Put);
      false
    with Failure s -> s = "callback"
  in
  expect "callback propagation" raised;
  expect "metadata resource limit"
    (match
       A.price
         (config ~lim:{ limits with max_row_visits = 1 } 1.)
         admitted Side.Put
     with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let p = model () in
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
  let sparse =
    good ~cfg { p with opens_at = 0.5 } (regular [ 0.5; 1. ]) Side.Put
  in
  let dense =
    good ~cfg
      { p with opens_at = 0.125 }
      (regular [ 0.125; 0.25; 0.375; 0.5; 0.625; 0.75; 0.875; 1. ])
      Side.Put
  in
  let american = unwrap (A.price cfg (unwrap (A.admit p)) Side.Put) in
  let error x =
    Option.fold ~none:0. ~some:(fun r -> r.A.observed_sum) x.A.refinement
  in
  expect "nested schedules"
    (sparse.value <= dense.value +. error sparse +. error dense);
  expect "American domination"
    (dense.value <= american.value +. error dense +. error american);
  let immediate =
    good ~cfg (model ~s:50. ()) (regular [ 0.; 0.5; 1. ]) Side.Put
  in
  expect "listed valuation obstacle" (immediate.value = 50.);
  (* Diffusion must couple the first positive node to the zero boundary;
     a drift-dominated upwind row can disconnect this witness. *)
  let low_spot = 0x1p-30 in
  let future =
    good ~cfg
      (model ~s:low_spot ~vol:0.4 ~opens:0.5 ())
      (regular [ 0.5; 1. ])
      Side.Put
  in
  (* Global discounted-strike cap and a feasible first-date European put:
     V <= K exp(-r t_first), V >= cap - S exp(-q t_first). *)
  let cap = 100. *. exp (-0.05 *. 0.5) in
  (* Backward Euler discounts a constant terminal strike by (1+r*h)^(-n),
     not exp(-r*t). Compare its discrete cap and accumulate the screened local
     residual/roundoff over steps (positive-rate inverse has norm <= 1).
     Boundary spread and observed refinement remain diagnostics, not proofs. *)
  let n = float future.work.finest_steps_per_slab in
  let discrete_cap = 100. *. exp (-.n *. log1p (0.05 *. 0.5 /. n)) in
  let arithmetic =
    float future.work.steps
    *. (future.maximum_residual +. future.maximum_roundoff_indicator)
    +. future.boundary_arithmetic_indicator
  in
  let spread =
    Option.fold ~none:0.
      ~some:(fun r -> r.A.boundary_half_spread)
      future.refinement
  in
  expect "next-right absorbing boundary upper"
    (future.value <= discrete_cap +. arithmetic +. spread);
  expect "next-right feasible stopping lower"
    (future.value
    >= cap -. (low_spot *. exp (-0.02 *. 0.5)) -. error future -. arithmetic);
  (* The minimum existing workspace leaves no room for optional preparation.
     Equal complete outcomes establish that reuse adds no required capacity. *)
  List.iter
    (fun r ->
      List.iter
        (fun cash ->
          (* A high diffusion rate makes the absorbing boundary materially
             observable at the spot anchor after spatial refinement. *)
          let p = model ~s:0x1p-30 ~vol:2. ~r ~opens:0.2 () in
          let ds = regular [ 0.2; 0.55; 1. ] in
          let cash = if cash then Some (spec [ (0.4, 5.) ]) else None in
          let a = unwrap (A.admit_bermudan ?cash p ds) in
          let reserved =
            (512 * limits.max_nodes)
            + (32 * limits.policy_iterations)
            + 65536
            + (1024 * Array.length ds)
            + if cash = None then 0 else (48 * limits.max_nodes) + 1024
          in
          let run extra cancel =
            A.price ~cancel
              (config
                 ~lim:{ limits with max_workspace_bytes = reserved + extra }
                 1.)
              a Side.Put
          in
          let expected = run 0 (fun () -> false) in
          expect "boundary fallback outcome"
            (if r >= 0. then Result.is_ok expected
             else expected = Error (A.Arithmetic_unresolved "global price cap"));
          List.iter
            (fun extra ->
              let actual = run extra (fun () -> false) in
              (match actual with
              | Ok x when r >= 0. ->
                  (* Before the first right/cash event, C(t)-S with
                     C(t)=K exp(-r*(opening-t)) is a discrete subsolution:
                     exp(-r*h)*(1+r*h) <= 1 and the -S row contributes
                     -h*q*S <= 0. Payoff and exterior values dominate it.
                     Allow accumulated residual/arithmetic screens, not an
                     observed refinement difference that can mask this fault. *)
                  let lower = (p.strike *. exp (-.r *. p.opens_at)) -. p.spot in
                  let arithmetic =
                    x.boundary_arithmetic_indicator
                    +. float x.work.steps
                       *. (x.maximum_residual +. x.maximum_roundoff_indicator)
                  in
                  expect "cached irregular feasible stopping lower"
                    (x.value >= lower -. arithmetic)
              | Error e when r >= 0. ->
                  failwith
                    ("cached irregular feasible stopping availability: "
                   ^ failure e)
              | _ -> ());
              expect "boundary reuse dependency identity" (actual = expected);
              List.iter
                (fun stop ->
                  let cancelled extra =
                    let calls = ref 0 in
                    let outcome =
                      run extra (fun () ->
                          incr calls;
                          !calls = stop)
                    in
                    (outcome, !calls)
                  in
                  expect "boundary reuse cancellation identity"
                    (cancelled extra = cancelled 0))
                [ 1; 50; 500 ])
            [ 128; 4096; 1048576 ])
        [ false; true ])
    [ 0.05; -0.05 ];
  expect "oversized optional boundary array falls back"
    (match
       A.price
         (config
            ~steps:((Sys.max_floatarray_length + 1) / 4)
            ~lim:{ limits with max_steps = 1; max_workspace_bytes = max_int }
            1.)
         admitted Side.Put
     with
    | Error (A.Arithmetic_unresolved "collapsed time coordinates") -> true
    | _ -> false);
  let run () = A.price cfg admitted Side.Put in
  let expected = run () in
  let workers = Array.init 2 (fun _ -> Domain.spawn run) in
  Array.iter
    (fun d -> expect "request ownership" (Domain.join d = expected))
    workers;
  print_endline "Bermudan contract controls passed"

let snapshot outcome =
  if Sys.getenv_opt "MORPHIQ_AMERICAN_SNAPSHOT" = Some "1" then
    ":snapshot="
    ^ Digest.to_hex
        (Digest.string (Marshal.to_string outcome [ Marshal.No_sharing ]))
  else ""

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
          let line = input_line ic in
          let raw, rights =
            match String.split_on_char '|' line with
            | [ raw; rights ] ->
                (String.trim raw, String.split_on_char ' ' (String.trim rights))
            | _ -> failwith "Bermudan delimiter"
          in
          let rec parse_rights = function
            | [] -> []
            | time :: side :: tail ->
                (decode time, phase side) :: parse_rights tail
            | _ -> failwith "truncated exercise rights"
          in
          let rights =
            match rights with
            | count :: tail ->
                let xs = parse_rights tail in
                if List.length xs <> int_of_string count then
                  failwith "exercise count";
                dates xs
            | _ -> failwith "missing exercise count"
          in
          match String.split_on_char ' ' raw with
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
              let outcome =
                A.price cfg (unwrap (A.admit_bermudan ~cash p rights)) side
              in
              match outcome with
              | Error e ->
                  Printf.printf "%s\tunavailable\t-\t%s\n%!" id
                    (failure e ^ snapshot outcome)
              | Ok x ->
                  Printf.printf
                    "%s\testimated\t%h\t%s:steps=%d:rows=%d:map=%d:roundoff=%h%s\n\
                     %!"
                    id x.value x.method_name x.work.steps x.work.row_visits
                    (Option.fold ~none:0
                       ~some:(fun m -> m.A.event_applications)
                       x.mapping)
                    x.maximum_roundoff_indicator (snapshot outcome))
          | _ -> failwith "cash protocol"
        done
      with End_of_file -> ())

let bench mode =
  let p = model ~opens:0.5 () in
  let admitted =
    match mode with
    | "none" -> unwrap (A.admit_bermudan p (regular [ 0.5; 1. ]))
    | "cash" ->
        unwrap
          (A.admit_bermudan
             ~cash:(spec ~opening:A.Before_cash [ (0.5, 5.) ])
             p
             (dates
                [ (0.5, A.Before_cash); (0.5, A.After_cash); (1., A.Regular) ]))
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
  let gc_before = Gc.quick_stat () in
  let bytes = Gc.allocated_bytes () and start = Unix.gettimeofday () in
  for _ = 1 to 3 do
    run ()
  done;
  let elapsed = (Unix.gettimeofday () -. start) /. 3. in
  let allocated = (Gc.allocated_bytes () -. bytes) /. 3. in
  let gc_after = Gc.stat () in
  Printf.printf
    "{\"mode\":%S,\"phase\":\"price\",\"calls\":3,\"seconds_per_call\":%.17g,\"allocated_bytes_per_call\":%.17g,\"minor_collections\":%d,\"major_collections\":%d,\"heap_words_after\":%d,\"live_words_after\":%d}\n"
    mode elapsed allocated
    (gc_after.minor_collections - gc_before.minor_collections)
    (gc_after.major_collections - gc_before.major_collections)
    gc_after.heap_words gc_after.live_words

let () =
  match Array.to_list Sys.argv with
  | [ _ ] -> controls ()
  | [ _; "--corpus"; path ] | [ _; "--"; path ] -> corpus path false
  | [ _; "--refined-corpus"; path ] -> corpus path true
  | [ _; "--bench"; mode ] -> bench mode
  | [ _; "--help" ] ->
      print_endline
        "bermudan [--corpus FILE|--refined-corpus FILE|--bench none/cash|-- \
         FILE|--version]"
  | [ _; "--version" ] -> print_endline "bermudan 1"
  | _ ->
      prerr_endline "unknown arguments";
      exit 2
