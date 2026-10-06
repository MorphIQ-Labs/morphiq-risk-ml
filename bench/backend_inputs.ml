(* Original project workload definitions, frozen from the #146 harness. *)
open Morphiq_risk
module A = Early_exercise.Bsm
module B = Batch.American
module P = Planner.American

external clock : unit -> float = "morphiq_bench_monotonic"

let get = function
  | Ok x -> x
  | Error _ -> failwith "campaign structural refusal"

let vol x = get (Vol.lognormal x)

let configuration tolerance =
  get
    (A.configure ~tolerance
       ~space_cells:
         (match Sys.getenv_opt "MORPHIQ_CAPTURE_CELLS" with
         | None -> 64
         | Some x -> int_of_string x)
       ~time_steps:64 ~domain_expansions:2
       ~limits:
         A.
           {
             max_nodes = 8192;
             max_steps = 131072;
             max_policy_solves = 1048576;
             max_row_visits = 100000000;
             max_workspace_bytes = 8388608;
             policy_iterations = 64;
           })

let cfg = configuration 1.
let strict = configuration 1e-12
let price c = B.Price { pricing = c; premium = false; exercise_regions = false }

let greeks =
  get
    (A.configure_greeks
       [
         get (A.request_greek ~tolerance:10. Delta);
         get (A.request_greek ~tolerance:10. Gamma);
       ])

let inverse =
  get
    (A.Implied_volatility.configure ~pricing:cfg ~lower:(vol 0.05)
       ~upper:(vol 0.6) ~width:0.01 ~max_evaluations:32)

let quote = get (A.Implied_volatility.quote 0x1.aa45024c11b87p+2)
let certificate = get (A.Certified.absolute_error_limit 1e-9)

let cases =
  [
    "call";
    "flat";
    "cash";
    "bermudan";
    "piecewise";
    "piecewise-cash";
    "greeks";
    "curve-greeks";
    "iv";
    "certified";
    "hard";
    "mixed";
  ]

type item = {
  position : P.position;
  request : offset:int -> spot:float -> B.request;
}

let years offset day = float (day - offset) /. 365.

let make_item kind index =
  let kind =
    if kind = "mixed" then
      [| "flat"; "cash"; "piecewise-cash"; "hard" |].(index mod 4)
    else kind
  in
  let id = string_of_int index in
  let is_cash = List.mem kind [ "cash"; "bermudan"; "piecewise-cash" ] in
  let cash =
    if is_cash then Some P.[| { day = 180; amount = 5. } |] else None
  in
  let exercise =
    if kind = "bermudan" then
      P.Bermudan
        P.
          [|
            { day = 90; side = A.Regular };
            { day = 180; side = A.Before_cash };
            { day = 180; side = A.After_cash };
            { day = 365; side = A.Regular };
          |]
    else
      P.American
        { opening = { day = 0; side = A.Regular }; expiry_side = A.Regular }
  in
  let side =
    if kind = "call" || kind = "certified" then Side.Call else Side.Put
  in
  let q = if side = Side.Call then 0. else 0.02 in
  let position model output =
    P.Position
      P.
        {
          id;
          factor = "S";
          currency = "USD";
          quantity = 1.;
          strike = 100.;
          expiry_day = 365;
          side;
          model;
          exercise;
          cash;
          outputs = [ output ];
        }
  in
  let cash_spec offset =
    if is_cash then
      Some
        A.
          {
            valuation_side = Regular;
            opening_side = Regular;
            expiry_side = Regular;
            dividends = [| { time = years offset 180; amount = 5. } |];
          }
    else None
  in
  if List.mem kind [ "piecewise"; "piecewise-cash"; "curve-greeks" ] then
    let model =
      P.Piecewise
        {
          rate = { initial = 0.05; changes = [| (180, -0.03) |] };
          dividend_yield = { initial = 0.02; changes = [| (180, 0.08) |] };
          volatility = { initial = vol 0.2; changes = [| (180, vol 0.35) |] };
        }
    in
    let output =
      if kind = "curve-greeks" then B.Output (B.Greeks (cfg, greeks))
      else B.Output (price cfg)
    in
    let request ~offset ~spot =
      let horizon = years offset 365 and knot = years offset 180 in
      let p =
        A.Piecewise.
          {
            spot;
            strike = 100.;
            time_to_expiry = horizon;
            opens_at = 0.;
            rate =
              get
                (Rate.create ~horizon ~initial:0.05
                   ~changes:[| (knot, -0.03) |]);
            dividend_yield =
              get
                (Yield.create ~horizon ~initial:0.02
                   ~changes:[| (knot, 0.08) |]);
            volatility =
              get
                (Volatility.create ~horizon ~initial:(vol 0.2)
                   ~changes:[| (knot, vol 0.35) |]);
          }
      in
      let a =
        get
          (match cash_spec offset with
          | None -> A.Piecewise.admit p
          | Some c -> A.Piecewise.admit_cash p c)
      in
      B.Request { id; model = B.Piecewise a; side; outputs = [ output ] }
    in
    { position = position model output; request }
  else
    let model =
      P.Constant { rate = 0.05; dividend_yield = q; volatility = vol 0.2 }
    in
    let output =
      match kind with
      | "greeks" -> B.Output (B.Greeks (cfg, greeks))
      | "iv" -> B.Output (B.Implied (inverse, quote))
      | "certified" -> B.Output (B.Certified_price certificate)
      | "hard" -> B.Output (price strict)
      | _ -> B.Output (price cfg)
    in
    let request ~offset ~spot =
      let p =
        A.
          {
            spot;
            strike = 100.;
            rate = 0.05;
            dividend_yield = q;
            volatility = vol 0.2;
            time_to_expiry = years offset 365;
            opens_at = (if kind = "bermudan" then years offset 90 else 0.);
          }
      in
      let a =
        get
          (if kind = "bermudan" then
             A.admit_bermudan ?cash:(cash_spec offset) p
               A.
                 [|
                   { time = years offset 90; side = Regular };
                   { time = years offset 180; side = Before_cash };
                   { time = years offset 180; side = After_cash };
                   { time = years offset 365; side = Regular };
                 |]
           else
             match cash_spec offset with
             | None -> A.admit p
             | Some c -> A.admit_cash p c)
      in
      B.Request { id; model = B.Constant a; side; outputs = [ output ] }
    in
    { position = position model output; request }

let scalar_operation : type k a.
    k B.model -> Side.t -> (k, a) B.operation -> (a, B.error) result =
 fun model side op ->
  match (model, op) with
  | B.Constant a, B.Price p ->
      Result.map_error
        (fun e -> B.Pricing e)
        (A.price ~premium:p.premium ~exercise_regions:p.exercise_regions
           p.pricing a side)
  | B.Piecewise a, B.Price p ->
      Result.map_error
        (fun e -> B.Pricing e)
        (A.Piecewise.price ~premium:p.premium
           ~exercise_regions:p.exercise_regions p.pricing a side)
  | B.Constant a, B.Greeks (c, g) ->
      Result.map_error (fun e -> B.Pricing e) (A.greeks c g a side)
  | B.Piecewise a, B.Greeks (c, g) ->
      Result.map_error (fun e -> B.Pricing e) (A.Piecewise.greeks c g a side)
  | B.Constant a, B.Implied (s, q) ->
      Result.map_error
        (fun e -> B.Inverse e)
        (A.Implied_volatility.solve s a side q)
  | B.Constant a, B.Certified_price limit ->
      Result.map_error
        (fun e -> B.Certification e)
        (A.Certified.price a side ~max_error:limit)
  | B.Piecewise _, (B.Implied _ | B.Certified_price _) ->
      (* Abstract model indices need not be provably distinct to this client. *)
      invalid_arg "unsupported piecewise operation"

let scalar (B.Request r) : B.row =
  {
    id = r.id;
    outcomes =
      List.map
        (fun (B.Output op) ->
          B.Outcome (op, scalar_operation r.model r.side op))
        r.outputs;
  }

let convert (B.Outcome (op, r)) =
  P.Outcome (op, Result.map_error (fun e -> P.Scalar e) r)

let payload x = Marshal.to_string x [ Marshal.No_sharing ]
let digest x = Digest.BLAKE256.to_hex (Digest.BLAKE256.string (payload x))

let complete n (c : Planner.completion) =
  if
    c.stop <> Planner.Complete || c.rows_committed <> n
    || c.calculations_committed <> n
  then failwith "incomplete campaign execution"

let classify (P.Outcome (op, r)) =
  match (op, r) with
  | B.Greeks (_, requests), Error _ ->
      (0, List.length (requests :> A.greek_request list), 0)
  | _, Error _ -> (0, 1, 0)
  | B.Greeks _, Ok g ->
      List.fold_left
        (fun (s, f, u) -> function
          | _, A.Greek_estimate _ -> (s + 1, f, u)
          | _, A.Greek_unavailable _ -> (s, f, u + 1)
          | _ -> (s, f + 1, u))
        (0, 0, 0) g.greeks
  | _, Ok _ -> (1, 0, 0)

let failure_name = function
  | A.Resource_limit _ -> "resource-limit"
  | Cancelled -> "cancelled"
  | Arithmetic_unresolved _ -> "arithmetic-unresolved"
  | Unrepresentable -> "unrepresentable"
  | Nonconvergence _ -> "nonconvergence"
  | Accuracy_not_demonstrated _ -> "accuracy-not-demonstrated"

let status (P.Outcome (op, result)) =
  let failure = function
    | P.Scalar (B.Pricing f) -> failure_name f
    | Scalar (B.Inverse (A.Implied_volatility.Pricing_failed f)) ->
        "iv-" ^ failure_name f
    | Scalar (B.Inverse A.Implied_volatility.Price_uncertainty_or_plateau) ->
        "iv-price-uncertainty"
    | Scalar (B.Inverse A.Implied_volatility.Evaluation_limit) ->
        "iv-evaluation-limit"
    | Scalar (B.Inverse _) -> "iv-refusal"
    | Scalar (B.Certification _) -> "certificate-refusal"
    | Post_expiry -> "post-expiry"
    | Admission _ | Volatility _ -> "admission-refusal"
  in
  match (op, result) with
  | B.Greeks (_, requests), Error e ->
      List.map (fun _ -> failure e) (requests :> A.greek_request list)
  | _, Error e -> [ failure e ]
  | B.Greeks _, Ok g ->
      List.map
        (function
          | _, A.Greek_estimate _ -> "estimated"
          | _, A.Greek_unavailable _ -> "unavailable"
          | _, A.Greek_failure f -> failure_name f
          | _, A.Greek_accuracy_not_demonstrated _ ->
              "accuracy-not-demonstrated")
        g.greeks
  | B.Price _, Ok _ -> [ "estimated" ]
  | B.Implied _, Ok _ -> [ "estimated-iv" ]
  | B.Certified_price _, Ok _ -> [ "certified" ]

let counts rows =
  List.fold_left
    (fun (s, f, u) (row : P.row) ->
      List.fold_left
        (fun (s, f, u) o ->
          let a, b, c = classify o in
          (s + a, f + b, u + c))
        (s, f, u) row.outcomes)
    (0, 0, 0) rows

let local_bytes () =
  let a, b, c = Gc.counters () in
  8. *. (a +. c -. b)

let total_bytes (s : Gc.stat) =
  8. *. (s.minor_words +. s.major_words -. s.promoted_words)

let scope_check () =
  List.iter
    (fun workers ->
      let before = total_bytes (Gc.stat ()) and coordinator = local_bytes () in
      let run () =
        let before = local_bytes () in
        for i = 1 to 1000 do
          ignore (Sys.opaque_identity (Array.make 1024 (float i)))
        done;
        local_bytes () -. before
      in
      let ds = Array.init workers (fun _ -> Domain.spawn run) in
      let local_sum = Array.fold_left (fun n d -> n +. Domain.join d) 0. ds in
      let coordinator = local_bytes () -. coordinator in
      let total = total_bytes (Gc.stat ()) -. before in
      let required = float (workers * 1000 * 1025 * 8) in
      if total < required || total < local_sum || coordinator >= required then
        failwith "allocation counter scope witness failed";
      Printf.printf "SCOPE\t%d\t%.0f\t%.0f\t%.0f\t%.0f\n%!" workers total
        local_sum coordinator required)
    [ 1; 2; 4 ]
