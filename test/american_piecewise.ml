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

module P = A.Piecewise

let piece_model (p : A.inputs) rates yields vols =
  let horizon = p.time_to_expiry in
  P.
    {
      spot = p.spot;
      strike = p.strike;
      opens_at = p.opens_at;
      time_to_expiry = horizon;
      rate = unwrap (P.Rate.create ~horizon ~initial:p.rate ~changes:rates);
      dividend_yield =
        unwrap
          (P.Yield.create ~horizon ~initial:p.dividend_yield ~changes:yields);
      volatility =
        unwrap
          (P.Volatility.create ~horizon ~initial:p.volatility
             ~changes:
               (Array.map (fun (t, v) -> (t, unwrap (Vol.lognormal v))) vols));
    }

let controls () =
  let original = [| (0.25, 0.1); (0.75, -0.1) |] in
  let p = piece_model (model ~s:0. ~r:(-0.1) ()) original [||] [||] in
  original.(0) <- (0.25, 100.);
  let exposed = P.Rate.changes p.rate in
  exposed.(0) <- (0.25, 200.);
  expect "curve ownership" ((P.Rate.changes p.rate).(0) = (0.25, 0.1));
  let value p =
    match P.price (config 0.001) (unwrap (P.admit p)) Side.Put with
    | Ok x -> x.value
    | Error e -> failwith (failure e)
  in
  expect "interior rate optimum"
    (abs_float (value p -. 102.53151205244288) < 1e-11);
  List.iter
    (fun xs ->
      expect "invalid curve partition"
        (Result.is_error (P.Rate.create ~horizon:1. ~initial:0. ~changes:xs)))
    [
      [| (0., 0.) |];
      [| (1., 0.) |];
      [| (0.5, 0.); (0.5, 0.) |];
      [| (0.7, 0.); (0.2, 0.) |];
      [| (nan, 0.) |];
      [| (0.5, infinity) |];
    ];
  expect "invalid horizon"
    (Result.is_error (P.Rate.create ~horizon:nan ~initial:0. ~changes:[||]));
  expect "initial validation at expiry"
    (Result.is_error (P.Rate.create ~horizon:0. ~initial:nan ~changes:[||]));
  expect "coverage" (Result.is_error (P.admit { p with time_to_expiry = 2. }));
  let a = unwrap (P.admit p) in
  expect "cancel"
    (P.price ~cancel:(fun () -> true) (config 1.) a Side.Put = Error A.Cancelled);
  expect "metadata resource"
    (match
       P.price
         (config ~lim:{ limits with max_workspace_bytes = 65536 } 1.)
         a Side.Put
     with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let c = model () in
  let constant = piece_model c [||] [||] [||] in
  let split =
    piece_model c
      [| (0.25, c.rate); (0.75, c.rate) |]
      [| (0.5, c.dividend_yield) |]
      [| (0.5, Vol.to_float c.volatility) |]
  in
  let cfg = config 1. in
  let expected = A.price cfg (unwrap (A.admit c)) Side.Put in
  expect "constant complete outcome"
    (P.price cfg (unwrap (P.admit constant)) Side.Put = expected);
  expect "redundant split complete outcome"
    (P.price cfg (unwrap (P.admit split)) Side.Put = expected);
  let refined = config ~cells:128 ~steps:128 1. in
  let price ?dates p side =
    let admitted =
      unwrap
        (match dates with
        | None -> P.admit p
        | Some ds -> P.admit_bermudan p ds)
    in
    match P.price refined admitted side with
    | Ok x -> x
    | Error e -> failwith (failure e)
  in
  let low = piece_model (model ~r:(-0.05) ()) [| (0.5, 0.15) |] [||] [||]
  and high = piece_model (model ~r:0.15 ()) [| (0.5, -0.05) |] [||] [||] in
  let lv = (price low Side.Put).value and hv = (price high Side.Put).value in
  expect "exercise distinguishes equal integrated rates" (lv > hv +. 1.);
  let varying_vol =
    piece_model (model ~vol:0.4 ()) [||] [||] [| (0.5, 0.1) |]
  in
  let vv = (price varying_vol Side.Put).value in
  expect "varying stencil independent reference"
    (abs_float (vv -. 10.673905247541096) +. 0.055185215741111904 <= 1.);
  (* Workspace size affects reuse, never the represented option or outcome.
     Compare both boundary choices through complete public results, including
     diagnostic/work counters and cancellation cadence. *)
  List.iter
    (fun (p, cash) ->
      let admitted =
        unwrap
          (match cash with None -> P.admit p | Some c -> P.admit_cash p c)
      in
      let count =
        3
        + Array.length (P.Rate.changes p.rate)
        + Array.length (P.Yield.changes p.dividend_yield)
        + Array.length (P.Volatility.changes p.volatility)
      in
      let reserved =
        (512 * limits.max_nodes)
        + (32 * limits.policy_iterations)
        + 65536 + (1024 * count)
        +
        match cash with
        | None -> 0
        | Some c -> (48 * limits.max_nodes) + (1024 * Array.length c.A.dividends)
      in
      List.iter
        (fun side ->
          let run surplus cancel_after =
            let calls = ref 0 in
            let result =
              P.price
                ~cancel:(fun () ->
                  incr calls;
                  !calls > cancel_after)
                (config ~cells:32 ~steps:32
                   ~lim:{ limits with max_workspace_bytes = reserved + surplus }
                   1.)
                admitted side
            in
            (result, !calls)
          in
          let expected = run 0 max_int in
          List.iter
            (fun surplus ->
              expect "bounded cache complete outcome and visits"
                (run surplus max_int = expected);
              expect "bounded cache cancellation cadence"
                (run surplus 400 = run 0 400))
            [ 512; 16384; 1048576 ])
        [ Side.Put; Side.Call ])
    [
      (varying_vol, None);
      ( piece_model (model ~q:(-0.05) ())
          [| (0.5, -0.03) |]
          [| (0.25, 0.08); (0.75, -0.02) |]
          [| (0.375, 0.3) |],
        None );
      ( piece_model (model ())
          [| (0.5, -0.03) |]
          [| (0.5, 0.08) |]
          [| (0.5, 0.35) |],
        Some (spec [ (0.5, 5.) ]) );
    ];
  let near =
    piece_model
      (model ~s:0x1p-20 ~r:(-0.1) ~vol:0.5 ())
      [| (0.25, 0.2); (0.75, -0.1) |]
      [||] [||]
  in
  let near_value = price near Side.Put in
  expect "interior future boundary"
    (abs_float (near_value.value -. 102.53151205244288) < 0.01);
  let p =
    piece_model
      (model ~s:0. ~r:(-0.1) ~opens:0.5 ())
      [| (0.25, 0.2); (0.75, -0.1) |]
      [||] [||]
  in
  expect "knots add no finite right"
    (abs_float
       ((price ~dates:(regular [ 0.5; 1. ]) p Side.Put).value
      -. 97.53099120283326)
    < 1e-11);
  let terminal base changes =
    piece_model (model ~vol:base ~opens:1. ()) [||] [||] changes
  in
  let early =
    (price ~dates:(regular [ 1. ]) (terminal 0.4 [| (0.5, 0.1) |]) Side.Call)
      .value
  and late =
    (price ~dates:(regular [ 1. ]) (terminal 0.1 [| (0.5, 0.4) |]) Side.Call)
      .value
  in
  expect "original integrated variance"
    (abs_float (early -. 12.699871169640508) < 1e-12 && early = late);
  let p =
    piece_model
      (model ~vol:0. ~k:90. ~r:0.1 ~q:0.05 ~t:8. ())
      [| (2., 0.25) |]
      [| (2., 0.125) |]
      [||]
  in
  expect "piecewise interior stationary exercise"
    (abs_float ((price p Side.Call).value -. 27.77777777777778) < 1e-11);
  let admitted = unwrap (P.admit low) in
  let calls = ref 0 in
  expect "mid-request cancellation"
    (P.price
       ~cancel:(fun () ->
         incr calls;
         !calls > 20)
       refined admitted Side.Put
    = Error A.Cancelled);
  expect "work budget"
    (match
       P.price
         (config ~lim:{ limits with max_row_visits = 10 } 1.)
         admitted Side.Put
     with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let concurrent = Domain.spawn (fun () -> P.price refined admitted Side.Put) in
  let local = P.price refined admitted Side.Put in
  expect "request ownership" (local = Domain.join concurrent);
  print_endline "piecewise controls passed"

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
          let raw, rights, rates, yields, vols =
            match String.split_on_char '|' line with
            | [ raw; rights; rates; yields; vols ] ->
                ( String.trim raw,
                  String.split_on_char ' ' (String.trim rights),
                  rates,
                  yields,
                  vols )
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
          let changes part =
            let rec parse = function
              | [] -> []
              | t :: v :: tail -> (decode t, decode v) :: parse tail
              | _ -> failwith "curve pairs"
            in
            match String.split_on_char ' ' (String.trim part) with
            | count :: tail ->
                let xs = parse tail in
                if List.length xs <> int_of_string count then
                  failwith "curve count";
                Array.of_list xs
            | _ -> failwith "missing curve count"
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
                let p =
                  piece_model p (changes rates) (changes yields) (changes vols)
                in
                let admitted =
                  if Array.length rights = 0 then P.admit_cash p cash
                  else P.admit_bermudan ~cash p rights
                in
                P.price cfg (unwrap admitted) side
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
  let admitted =
    match mode with
    | "none" ->
        unwrap
          (P.admit
             (piece_model (model ())
                [| (0.25, 0.08); (0.75, -0.03) |]
                [| (0.5, 0.06) |]
                [| (0.375, 0.3) |]))
    | "cash" ->
        unwrap
          (P.admit_cash
             (piece_model (model ())
                [| (0.5, -0.03) |]
                [| (0.5, 0.08) |]
                [| (0.5, 0.35) |])
             (spec [ (0.5, 5.) ]))
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
    match P.price cfg admitted Side.Put with
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
        "american-piecewise [--corpus FILE|--refined-corpus FILE|-- \
         FILE|--version]"
  | [ _; "--version" ] -> print_endline "american-piecewise 1"
  | _ ->
      prerr_endline "unknown arguments";
      exit 2
