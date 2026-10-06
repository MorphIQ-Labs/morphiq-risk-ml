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
      max_steps = 458752;
      max_policy_solves = 3670016;
      max_row_visits = 2800000000;
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

let greek_name = function
  | A.Delta -> "delta"
  | A.Gamma -> "gamma"
  | A.Vega -> "vega"
  | A.Rho -> "rho"
  | A.Theta -> "theta"

let quantities = [ A.Delta; A.Gamma; A.Vega; A.Rho; A.Theta ]

let requests ?(bump = 0x1p-10) loose =
  let targets =
    if loose then [ 0.02; 0.002; 1.; 1.; 0.005 ]
    else [ 0.001; 0.0001; 0.05; 0.05; 0.0001 ]
  in
  unwrap
    (A.configure_greeks
       (List.map2
          (fun quantity tolerance ->
            unwrap
              (A.request_greek
                 ?bump:
                   (if quantity = A.Vega || quantity = A.Rho then Some bump
                    else None)
                 ~tolerance quantity))
          quantities targets))

let diagnostics (d : A.greek_diagnostics) =
  Printf.sprintf "stencil=%h;arithmetic=%h;price=%h;refinement=%s;bump=%s"
    d.stencil_change d.arithmetic_indicator d.amplified_price_indicator
    (match d.derivative_refinement with
    | None -> "none"
    | Some r ->
        Printf.sprintf "%h,%h,%h,%h,%h,%h,%h,%h" (fst r.space_changes)
          (snd r.space_changes) (fst r.time_changes) (snd r.time_changes)
          (fst r.domain_changes) (snd r.domain_changes) r.boundary_half_spread
          r.observed_sum)
    (match d.bump_changes with
    | None -> "none"
    | Some (a, b) -> Printf.sprintf "%h,%h" a b)

let print_result id = function
  | Error f ->
      List.iter
        (fun q ->
          Printf.printf "%s\t%s\tprice_failure\t-\t%s\t-\n%!" id (greek_name q)
            (failure f))
        quantities
  | Ok (r : A.estimated_greeks) ->
      List.iter
        (fun (q, outcome) ->
          let status, value, detail =
            match outcome with
            | A.Greek_estimate v ->
                ( "estimated",
                  Printf.sprintf "%h" v.value,
                  diagnostics v.diagnostics )
            | A.Greek_unavailable reason -> ("unavailable", "-", reason)
            | A.Greek_failure f -> ("failure", "-", failure f)
            | A.Greek_accuracy_not_demonstrated d ->
                ("unresolved", "-", diagnostics d)
          in
          Printf.printf "%s\t%s\t%s\t%s\t%s\t%h\n%!" id (greek_name q) status
            value detail r.price.value)
        r.greeks

let analytic_controls () =
  (* Independent 80/160-digit original-input price differentiation, retained in
     docs/evidence/american-greeks/references-v1.json. *)
  let call =
    piece_model (model ~opens:1. ())
      [| (0.25, -0.02); (0.75, 0.08) |]
      [| (0.5, -0.01) |]
      [| (0.5, 0.4) |]
  in
  let put =
    piece_model (model ~opens:1. ())
      [| (0.5, -0.05) |]
      [| (0.25, 0.04) |]
      [| (0.75, 0.1) |]
  in
  let expected =
    [
      ( call,
        Side.Call,
        [
          0x1.29c73d0c1a9c6p-1;
          0x1.9210481b463c4p-7;
          0x1.267aeccff9f12p+5;
          0x1.6715fe9f67b15p+5;
          -0x1.3d5d35a90426fp-7;
        ] );
      ( put,
        Side.Put,
        [
          -0x1.0babea268b401p-1;
          0x1.5c35508a58752p-6;
          0x1.298a8e9237162p+5;
          -0x1.e985d9dc03069p+5;
          -0x1.91982b87aef31p-8;
        ] );
    ]
  in
  List.iter
    (fun (p, side, values) ->
      let admitted = unwrap (P.admit p) in
      let before = P.inputs admitted in
      let result =
        unwrap (P.greeks (config 1.) (requests true) admitted side)
      in
      List.iter2
        (fun (q, expected) target ->
          match List.assoc q result.greeks with
          | A.Greek_estimate g ->
              expect
                ("independent integrated " ^ greek_name q)
                (abs_float (g.value -. expected) <= target)
          | _ -> failwith ("integrated Greek declined: " ^ greek_name q))
        (List.combine quantities values)
        [ 0.001; 0.0001; 0.05; 0.05; 0.0001 ];
      expect "all parallel prices retained"
        (List.length result.perturbation_prices = 12);
      List.iter
        (fun (x : A.perturbation_price) ->
          expect "identified parallel price"
            (x.shift <> 0. && (x.quantity = A.Vega || x.quantity = A.Rho)))
        result.perturbation_prices;
      expect "admitted input ownership" (before = P.inputs admitted))
    expected;
  let p = unwrap (A.admit (model ~opens:1. ())) in
  let tiny =
    unwrap
      (A.configure_greeks
         [ unwrap (A.request_greek ~bump:0x1p-100 ~tolerance:1. A.Rho) ])
  in
  let result = unwrap (A.greeks (config 1.) tiny p Side.Put) in
  expect "do not silently round parallel shifts"
    (match List.assoc A.Rho result.greeks with
    | A.Greek_unavailable _ -> true
    | _ -> false);
  let calls = ref 0 in
  let cancel () =
    incr calls;
    !calls >= 5
  in
  expect "cancel during Greek preparation"
    (A.greeks ~cancel (config 1.) (requests true) p Side.Put = Error A.Cancelled);
  expect "whole-request row budget"
    (match
       A.greeks
         (config ~lim:{ limits with max_row_visits = 1 } 1.)
         (requests true) p Side.Put
     with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let cusp = unwrap (A.admit (model ~r:0. ~q:0. ~vol:0. ())) in
  let rho =
    unwrap
      (A.configure_greeks
         [ unwrap (A.request_greek ~bump:0x1p-10 ~tolerance:1. A.Rho) ])
  in
  let x = unwrap (A.greeks (config 1.) rho cusp Side.Call) in
  expect "central bump average is not a derivative at a stopping kink"
    (match List.assoc A.Rho x.greeks with
    | A.Greek_accuracy_not_demonstrated d -> d.stencil_change > 1.
    | _ -> false);
  let raised =
    try
      ignore
        (A.greeks
           ~cancel:(fun () -> raise Exit)
           (config 1.) (requests true) p Side.Put);
      false
    with Exit -> true
  in
  expect "callback exceptions propagate" raised

let numerical_controls () =
  let p =
    piece_model (model ())
      [| (0.25, 0.08); (0.75, -0.03) |]
      [| (0.5, 0.06) |]
      [| (0.375, 0.3) |]
  in
  let lim =
    {
      limits with
      max_steps = 1835008;
      max_policy_solves = 14680064;
      max_row_visits = 14000000000;
      max_nodes = 8192;
      max_workspace_bytes = 8388608;
    }
  in
  let cfg = config ~lim ~cells:128 ~steps:128 1. in
  let x = unwrap (P.greeks cfg (requests true) (unwrap (P.admit p)) Side.Put) in
  (* Pinned independent QuantLib exact-Time comparison, 128/256/512 refinement;
     retain its empirical uncertainty, including parallel-bump/time-roll error. *)
  let values =
    [
      -0x1.b076b4276afbfp-2;
      0x1.d1a83e803e808p-7;
      0x1.2a1cf109d5e00p+5;
      -0x1.a0fa8826fdc00p+5;
      -0x1.833d9a7de5591p-9;
    ]
  and radii =
    [
      0x1.b43eee2ee0000p-16;
      0x1.d98a18df64000p-15;
      0x1.f0e2b2429cf11p-7;
      0x1.651ca8050f510p-4;
      0x1.0573646c5c980p-14;
    ]
  in
  List.iter2
    (fun ((q, reference), radius) target ->
      match List.assoc q x.greeks with
      | A.Greek_estimate g ->
          expect
            ("stochastic continuation " ^ greek_name q)
            (abs_float (g.value -. reference) +. radius <= target)
      | _ -> failwith ("stochastic Greek unavailable: " ^ greek_name q))
    (List.combine (List.combine quantities values) radii)
    [ 0.02; 0.002; 1.; 1.; 0.005 ];
  let cash =
    spec ~valuation:A.Before_cash ~opening:A.Before_cash [ (0., 5.) ]
  in
  let admitted = unwrap (A.admit_cash (model ~s:5. ()) cash) in
  let req =
    unwrap
      (A.configure_greeks
         [
           unwrap (A.request_greek ~tolerance:0.02 A.Delta);
           unwrap (A.request_greek ~tolerance:0.002 A.Gamma);
         ])
  in
  let x = unwrap (A.greeks (config 1.) req admitted Side.Put) in
  List.iter
    (fun (_, outcome) ->
      expect "valuation liquidation kink is not a central derivative"
        (match outcome with A.Greek_unavailable _ -> true | _ -> false))
    x.greeks

let controls () =
  analytic_controls ();
  numerical_controls ();
  let req = requests true in
  expect "empty Greeks" (Result.is_error (A.configure_greeks []));
  let d = unwrap (A.request_greek ~tolerance:0.01 A.Delta) in
  expect "duplicate Greeks" (Result.is_error (A.configure_greeks [ d; d ]));
  expect "invalid tolerance"
    (Result.is_error (A.request_greek ~tolerance:nan A.Delta));
  expect "missing bump" (Result.is_error (A.request_greek ~tolerance:1. A.Vega));
  expect "unexpected bump"
    (Result.is_error (A.request_greek ~bump:0.01 ~tolerance:1. A.Delta));
  let p = model ~opens:1. () in
  let a = unwrap (A.admit p) in
  let cfg = config 1. in
  expect "cancel Greek request"
    (A.greeks ~cancel:(fun () -> true) cfg req a Side.Put = Error A.Cancelled);
  expect "bounded Greek workspace"
    (match
       A.greeks
         (config ~lim:{ limits with max_workspace_bytes = 65536 } 1.)
         req a Side.Put
     with
    | Error (A.Resource_limit _) -> true
    | _ -> false);
  let european = unwrap (A.greeks cfg req a Side.Put) in
  print_result "european-control" (Ok european);
  List.iter
    (fun (_, v) ->
      expect "European smooth capability"
        (match v with A.Greek_estimate _ -> true | _ -> false))
    european.greeks;
  let x =
    unwrap (A.greeks cfg req (unwrap (A.admit (model ~t:0. ()))) Side.Put)
  in
  expect "expiry strike kink unavailable"
    (match List.assoc A.Delta x.greeks with
    | A.Greek_unavailable _ -> true
    | _ -> false);
  let x =
    unwrap (A.greeks cfg req (unwrap (A.admit (model ~vol:0. ()))) Side.Put)
  in
  expect "ordinary vega at zero unavailable"
    (match List.assoc A.Vega x.greeks with
    | A.Greek_unavailable _ -> true
    | _ -> false);
  let x =
    unwrap (A.greeks cfg req (unwrap (A.admit (model ~s:40. ()))) Side.Put)
  in
  print_result "exercise-control" (Ok x);
  List.iter
    (fun (q, target) ->
      match List.assoc q x.greeks with
      | A.Greek_estimate g ->
          expect "exercise interior Greek"
            (abs_float (g.value -. target) < 1e-10)
      | _ -> failwith "exercise interior unavailable")
    [ (A.Delta, -1.); (A.Gamma, 0.); (A.Theta, 0.) ];
  let b =
    A.greeks (config ~cells:128 1.)
      (unwrap
         (A.configure_greeks
            [ unwrap (A.request_greek ~tolerance:0.005 A.Theta) ]))
      (unwrap (A.admit_bermudan (model ()) (regular [ 0.; 1. ])))
      Side.Put
  in
  print_result "bermudan-event" b;
  let x = unwrap b in
  expect "Bermudan valuation theta unavailable"
    (match List.assoc A.Theta x.greeks with
    | A.Greek_unavailable _ -> true
    | _ -> false);
  print_endline "American Greek controls passed"

let decode s = Int64.float_of_bits (Int64.of_string ("0x" ^ s))

let phase = function
  | "0" -> A.Regular
  | "1" -> A.Before_cash
  | "2" -> A.After_cash
  | _ -> failwith "phase"

let corpus path refined loose =
  let lim, cells, steps =
    if refined then
      ( {
          limits with
          max_nodes = 8192;
          max_steps = 1835008;
          max_policy_solves = 14680064;
          max_row_visits = 14000000000;
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
            :: valuation :: opening :: expiry :: count :: ds ->
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
                P.greeks cfg (requests loose) (unwrap admitted) side
              in
              print_result id outcome
          | _ -> failwith "cash protocol"
        done
      with End_of_file -> ())

let () =
  match Array.to_list Sys.argv with
  | [ _ ] -> controls ()
  | [ _; "--corpus"; path; mode ] -> corpus path false (mode = "loose")
  | [ _; "--refined-corpus"; path; mode ] -> corpus path true (mode = "loose")
  | [ _; "--help" ] ->
      print_endline
        "american-greeks [--corpus FILE primary|loose | --refined-corpus FILE \
         primary|loose | --version]"
  | [ _; "--version" ] -> print_endline "american-greeks 1"
  | _ ->
      prerr_endline "invalid arguments";
      exit 2
