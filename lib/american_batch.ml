module A = Early_exercise.Bsm
module I = A.Implied_volatility
module C = Plan_encoding

type constant
type piecewise

type _ model =
  | Constant : A.admitted -> constant model
  | Piecewise : A.Piecewise.admitted -> piecewise model

type (_, _) operation =
  | Price : {
      pricing : A.configuration;
      premium : bool;
      exercise_regions : bool;
    }
      -> ('k, A.estimated_price) operation
  | Greeks :
      A.configuration * A.greek_configuration
      -> ('k, A.estimated_greeks) operation
  | Implied : I.settings * I.quote -> (constant, I.estimated_interval) operation
  | Certified_price :
      A.Certified.absolute_error_limit
      -> (constant, A.Certified.price) operation

type 'k output = Output : ('k, 'a) operation -> 'k output

type request =
  | Request : {
      id : string;
      model : 'k model;
      side : Side.t;
      outputs : 'k output list;
    }
      -> request

type error =
  | Pricing of A.failure
  | Certification of A.Certified.error
  | Inverse of I.error

type outcome = Outcome : ('k, 'a) operation * ('a, error) result -> outcome
type row = { id : string; outcomes : outcome list }

type limits = {
  max_requests : int;
  max_outputs : int;
  max_solver_workspace_bytes : int;
}

type t = { requests : request array; encoding : string }

let configuration b (cfg : A.configuration) =
  C.float b cfg.tolerance;
  List.iter (C.integer b)
    [
      cfg.space_cells;
      cfg.time_steps;
      cfg.domain_expansions;
      cfg.limits.max_nodes;
      cfg.limits.max_steps;
      cfg.limits.max_policy_solves;
      cfg.limits.max_row_visits;
      cfg.limits.max_workspace_bytes;
      cfg.limits.policy_iterations;
    ]

let output_encoding (type k) (Output op : k output) =
  let b = C.create () in
  (match op with
  | Price p ->
      C.token b "estimated-price";
      configuration b p.pricing;
      C.boolean b p.premium;
      C.boolean b p.exercise_regions
  | Greeks (cfg, requests) ->
      C.token b "estimated-greeks";
      configuration b cfg;
      let requests = (requests :> A.greek_request list) in
      C.integer b (List.length requests);
      List.iter
        (fun (r : A.greek_request) ->
          C.token b
            (match r.quantity with
            | Delta -> "delta"
            | Gamma -> "gamma"
            | Vega -> "vega/unit-vol"
            | Rho -> "rho/unit-rate"
            | Theta -> "theta/day");
          C.float b r.tolerance;
          C.option C.float b r.bump)
        requests
  | Implied (s, q) ->
      C.token b "estimated-constant-sigma-interval";
      configuration b s.pricing;
      C.float b (Vol.to_float s.lower);
      C.float b (Vol.to_float s.upper);
      C.float b s.width;
      C.integer b s.max_evaluations;
      C.float b (q :> float)
  | Certified_price limit ->
      C.token b "certified-reduction-price";
      C.float b (limit :> float));
  C.contents b

let output_workspace (type k) (Output op : k output) =
  match op with
  | Price p -> p.pricing.limits.max_workspace_bytes
  | Greeks (cfg, _) -> cfg.limits.max_workspace_bytes
  | Implied (s, _) -> s.pricing.limits.max_workspace_bytes
  | Certified_price _ -> 0

let side b = function Side.Call -> C.token b "call" | Put -> C.token b "put"

let event_side b = function
  | A.Regular -> C.token b "regular"
  | Before_cash -> C.token b "before-cash"
  | After_cash -> C.token b "after-cash"

let cash b (c : A.cash_specification) =
  List.iter (event_side b) [ c.valuation_side; c.opening_side; c.expiry_side ];
  C.array
    (fun b (d : A.dividend) ->
      C.float b d.time;
      C.float b d.amount)
    b c.dividends

let exercise b ds =
  C.array
    (fun b (d : A.exercise_instant) ->
      C.float b d.time;
      event_side b d.side)
    b ds

let common b spot strike opens expiry =
  List.iter (C.float b) [ spot; strike; opens; expiry ]

let model_encoding : type k. C.t -> k model -> unit =
 fun b -> function
  | Constant a ->
      C.token b "constant-bsm";
      let p = A.inputs a in
      common b p.spot p.strike p.opens_at p.time_to_expiry;
      List.iter (C.float b)
        [ p.rate; p.dividend_yield; Vol.to_float p.volatility ];
      C.option cash b (A.cash_specification a);
      C.option exercise b (A.exercise_schedule a)
  | Piecewise a ->
      C.token b "piecewise-bsm";
      let p = A.Piecewise.inputs a in
      common b p.spot p.strike p.opens_at p.time_to_expiry;
      let curve horizon initial changes =
        C.float b horizon;
        C.float b initial;
        C.array
          (fun b (t, x) ->
            C.float b t;
            C.float b x)
          b changes
      in
      curve
        (A.Piecewise.Rate.horizon p.rate)
        (A.Piecewise.Rate.initial p.rate)
        (A.Piecewise.Rate.changes p.rate);
      curve
        (A.Piecewise.Yield.horizon p.dividend_yield)
        (A.Piecewise.Yield.initial p.dividend_yield)
        (A.Piecewise.Yield.changes p.dividend_yield);
      curve
        (A.Piecewise.Volatility.horizon p.volatility)
        (Vol.to_float (A.Piecewise.Volatility.initial p.volatility))
        (Array.map
           (fun (t, x) -> (t, Vol.to_float x))
           (A.Piecewise.Volatility.changes p.volatility));
      C.option cash b (A.Piecewise.cash_specification a);
      C.option exercise b (A.Piecewise.exercise_schedule a)

let compile ~limits requests =
  let exception Invalid of string in
  let require p s = if not p then raise (Invalid s) in
  try
    require
      (limits.max_requests >= 0 && limits.max_outputs >= 0
      && limits.max_solver_workspace_bytes >= 0)
      "invalid batch limits";
    require (Array.length requests <= limits.max_requests) "batch request limit";
    let requests = Array.copy requests and ids = Hashtbl.create 16 in
    let count = ref 0 and b = C.create () in
    C.token b "american-batch-v1";
    List.iter (C.integer b)
      [
        limits.max_requests;
        limits.max_outputs;
        limits.max_solver_workspace_bytes;
      ];
    C.integer b (Array.length requests);
    Array.iter
      (fun (Request r) ->
        require
          (r.id <> "" && not (Hashtbl.mem ids r.id))
          "duplicate/empty batch ID";
        Hashtbl.add ids r.id ();
        let n = List.length r.outputs in
        require (n <= limits.max_outputs - !count) "batch output limit";
        count := !count + n;
        C.token b r.id;
        model_encoding b r.model;
        side b r.side;
        C.integer b n;
        List.iter
          (fun o ->
            require
              (output_workspace o <= limits.max_solver_workspace_bytes)
              "batch solver workspace limit";
            C.token b (output_encoding o))
          r.outputs)
      requests;
    Ok { requests; encoding = C.contents b }
  with Invalid s -> Error s

let evaluate_operation : type k a.
    (unit -> bool) -> k model -> Side.t -> (k, a) operation -> (a, error) result
    =
 fun cancel model side op ->
  match (op, model) with
  | Price p, Constant a ->
      Result.map_error
        (fun e -> Pricing e)
        (A.price ~cancel ~premium:p.premium ~exercise_regions:p.exercise_regions
           p.pricing a side)
  | Price p, Piecewise a ->
      Result.map_error
        (fun e -> Pricing e)
        (A.Piecewise.price ~cancel ~premium:p.premium
           ~exercise_regions:p.exercise_regions p.pricing a side)
  | Greeks (cfg, g), Constant a ->
      Result.map_error (fun e -> Pricing e) (A.greeks ~cancel cfg g a side)
  | Greeks (cfg, g), Piecewise a ->
      Result.map_error
        (fun e -> Pricing e)
        (A.Piecewise.greeks ~cancel cfg g a side)
  | Implied (s, q), Constant a ->
      Result.map_error (fun e -> Inverse e) (I.solve ~cancel s a side q)
  | Certified_price limit, Constant a ->
      Result.map_error
        (fun e -> Certification e)
        (A.Certified.price ~cancel a side ~max_error:limit)

let evaluate ?(cancel = fun () -> false) (Request r) =
  {
    id = r.id;
    outcomes =
      List.map
        (fun (Output op) ->
          Outcome (op, evaluate_operation cancel r.model r.side op))
        r.outputs;
  }

let execute ?cancel t = Array.map (evaluate ?cancel) t.requests
let length t = Array.length t.requests

let manifest t =
  "american-batch-manifest-v1\nocaml=" ^ Sys.ocaml_version ^ "\nword-size="
  ^ string_of_int Sys.word_size
  ^ "\n" ^ t.encoding
