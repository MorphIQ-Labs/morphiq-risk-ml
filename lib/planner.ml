type market =
  | Spot_market of { spot : float; volatility : Vol.lognormal Vol.t }
  | Forward_market of { forward : float; volatility : Vol.lognormal Vol.t }
  | Normal_market of { forward : float; volatility : Vol.normal Vol.t }

type factor = { name : string; market : market }

type model =
  | Bsm of { dividend_yield : float }
  | Black76
  | Displaced of float
  | Bachelier

type position = {
  id : string;
  factor : string;
  rate_factor : string;
  currency : string;
  quantity : float;
  model : model;
  strike : float;
  expiry_day : int;
  rate : float;
  side : Side.t;
}

type 'c output = Output : ('c, 'a) Production.quantity * 'a -> 'c output
type day_count = Actual_365_fixed | Actual_360
type output_mode = Stream | Aggregate_only

type limits = {
  max_instruments : int;
  max_scenarios : int;
  max_calculations : int;
  tile_rows : int;
  max_workers : int;
  max_buffered_results : int;
  max_groups : int;
}

type explanation = {
  snapshot_id : string;
  kernels : string list;
  limits : limits;
  output_mode : output_mode;
  dependency_reuse : string;
  instruments : int;
  scenarios : int;
  calculations : int;
  tiles : int;
  raw_value_error_bytes : int;
  buffered_results : int;
  groups : int;
  plan_id : string;
  convention : string;
}

type coordinate = Lognormal | Normal

type bucket = {
  currency : string;
  factor : string;
  rate_factor : string;
  model : model;
  coordinate : coordinate;
  quantity_name : string;
}

module Buckets = Map.Make (struct
  type t = bucket

  let compare = compare
end)

type assurance = Certified | Fast_price

type t = {
  assurance : assurance;
  portfolio : position array;
  market : factor array;
  factor_indices : int array;
  scenarios : Scenario.t;
  base_day : int;
  day_count : day_count;
  lognormal_outputs : Vol.lognormal output list;
  normal_outputs : Vol.normal output list;
  output_mode : output_mode;
  limits : limits;
  explanation : explanation;
  buckets : int Buckets.t;
  bucket_keys : bucket array;
  tiles_per_scenario : int;
}

let number : type c a. (c, a) Production.quantity -> a -> float =
 fun q v ->
  match q with
  | Price -> v
  | Delta -> v
  | Gamma -> v
  | Rho -> v
  | Theta -> (v :> float)
  | Charm -> (v :> float)
  | Color -> (v :> float)
  | Vega -> (v :> float)
  | Vanna -> (v :> float)
  | Volga -> (v :> float)
  | Veta -> (v :> float)

let quantity_name : type c a. (c, a) Production.quantity -> string = function
  | Price -> "price"
  | Delta -> "delta"
  | Gamma -> "gamma"
  | Rho -> "rho"
  | Theta -> "theta/day"
  | Charm -> "charm/day"
  | Color -> "color/day"
  | Vega -> "vega/unit-vol"
  | Vanna -> "vanna/unit-vol"
  | Volga -> "volga/unit-vol^2"
  | Veta -> "veta/day/unit-vol"

let coordinate = function Bachelier -> Normal | _ -> Lognormal

let bucket (p : position) name =
  {
    currency = p.currency;
    factor = p.factor;
    rate_factor = p.rate_factor;
    model = p.model;
    coordinate = coordinate p.model;
    quantity_name = name;
  }

exception Plan_error of string

let require ok s = if not ok then raise (Plan_error s)

let product a b =
  require
    (a >= 0 && b >= 0 && (a = 0 || b <= max_int / a))
    "cardinality overflow";
  a * b

let sum a b =
  require (a <= max_int - b) "cardinality overflow";
  a + b

let convention =
  "planner-v1;frozen-market;roll-fixed-expiry;indexed-fma-v1;ordered-enclosure-v1"

let compile_common ~assurance ~snapshot_id ~base_day ~day_count ~portfolio
    ~market ~scenarios ~lognormal_outputs ~normal_outputs ~output_mode ~limits =
  let fast = assurance = Fast_price in
  let convention =
    if fast then
      "planner-fast-v1;frozen-market;roll-fixed-expiry;indexed-fma-v1;unweighted-price-stream"
    else convention
  in
  try
    require
      (snapshot_id <> "" && base_day >= -1000000000 && base_day <= 1000000000)
      "invalid snapshot identity/base date";
    require
      (limits.max_instruments >= 0
      && limits.max_scenarios >= 0
      && limits.max_calculations >= 0
      && limits.tile_rows > 0 && limits.max_workers > 0
      && limits.max_buffered_results >= 0
      && limits.max_groups >= 0)
      "invalid resource policy";
    let instruments = Array.length portfolio
    and scenario_count = Scenario.count scenarios in
    require
      (instruments <= limits.max_instruments
      && scenario_count <= limits.max_scenarios)
      "dimension limit exceeded";
    let validate_outputs : type c. c output list -> unit =
     fun outputs ->
      let names =
        List.map
          (fun (Output (q, v)) ->
            require
              (Float.is_finite (number q v) && number q v >= 0.)
              "invalid accuracy";
            quantity_name q)
          outputs
      in
      require
        (List.length names = List.length (List.sort_uniq String.compare names))
        "duplicate output"
    in
    validate_outputs lognormal_outputs;
    validate_outputs normal_outputs;
    let market = Array.copy market and portfolio = Array.copy portfolio in
    let factors = Hashtbl.create (Array.length market) in
    Array.iteri
      (fun i f ->
        require
          (f.name <> "" && not (Hashtbl.mem factors f.name))
          "duplicate/empty factor";
        Hashtbl.add factors f.name i;
        let x =
          match f.market with
          | Spot_market m -> m.spot
          | Forward_market m -> m.forward
          | Normal_market m -> m.forward
        in
        require (Float.is_finite x) "nonfinite base market")
      market;
    List.iter
      (fun (name, field) ->
        require (Hashtbl.mem factors name) "unknown scenario factor";
        let m = market.(Hashtbl.find factors name).market in
        require
          (match (field, m) with
          | Scenario.Spot, Spot_market _
          | Forward, (Forward_market _ | Normal_market _)
          | Lognormal_volatility, (Spot_market _ | Forward_market _)
          | Normal_volatility, Normal_market _ ->
              true
          | _ -> false)
          "scenario coordinate mismatch")
      (Scenario.bindings scenarios);
    let factor_currencies = Hashtbl.create (Array.length market) in
    let ids = Hashtbl.create instruments
    and calculations_per_scenario = ref 0
    and buckets = ref Buckets.empty
    and group_count = ref 0 in
    let factor_indices =
      Array.mapi
        (fun _ (p : position) ->
          require
            (p.id <> "" && p.currency <> "" && p.rate_factor <> ""
            && not (Hashtbl.mem ids p.id))
            "duplicate/empty instrument identity";
          Hashtbl.add ids p.id ();
          require
            (Float.is_finite p.quantity && Float.is_finite p.rate
           && Float.is_finite p.strike
            && p.expiry_day >= -1000000000
            && p.expiry_day <= 1000000000)
            "invalid instrument terms";
          require (Hashtbl.mem factors p.factor) "unbound instrument factor";
          let fi = Hashtbl.find factors p.factor in
          (match Hashtbl.find_opt factor_currencies p.factor with
          | None -> Hashtbl.add factor_currencies p.factor p.currency
          | Some currency ->
              require (currency = p.currency)
                "market factor has conflicting denominations");
          require
            (match (p.model, market.(fi).market) with
            | Bsm b, Spot_market _ -> Float.is_finite b.dividend_yield
            | Black76, Forward_market _ -> true
            | Displaced d, Forward_market _ -> Float.is_finite d
            | Bachelier, Normal_market _ -> true
            | _ -> false)
            "model/factor coordinate mismatch";
          let names =
            if fast then [ "price" ]
            else
              match p.model with
              | Bachelier ->
                  List.map
                    (fun (Output (q, _)) -> quantity_name q)
                    normal_outputs
              | _ ->
                  List.map
                    (fun (Output (q, _)) -> quantity_name q)
                    lognormal_outputs
          in
          calculations_per_scenario :=
            sum !calculations_per_scenario (List.length names);
          List.iter
            (fun name ->
              let key = bucket p name in
              if not (Buckets.mem key !buckets) then (
                (* The map comparator owns group equality, including signed zero.
                   Check before incrementing, so max_int is safe as a limit. *)
                require
                  (!group_count < limits.max_groups)
                  "aggregation group limit exceeded";
                incr group_count;
                (* Keep the first representative of equivalent input keys. *)
                buckets := Buckets.add key 0 !buckets))
            (if fast then [] else names);
          fi)
        portfolio
    in
    ignore (product scenario_count instruments);
    let calculations = product scenario_count !calculations_per_scenario in
    require
      (calculations <= limits.max_calculations)
      "calculation limit exceeded";
    let tiles_per_scenario =
      (instruments / limits.tile_rows)
      + if instruments mod limits.tile_rows = 0 then 0 else 1
    in
    let tiles = product scenario_count tiles_per_scenario in
    let buffered_results =
      product
        (product
           (min instruments limits.tile_rows)
           (min limits.max_workers tiles))
        (max 1
           (max (List.length normal_outputs) (List.length lognormal_outputs)))
    in
    require
      (buffered_results <= limits.max_buffered_results)
      "in-flight result limit exceeded";
    let raw_value_error_bytes = product calculations (if fast then 8 else 16) in
    let bucket_keys =
      Array.of_list (List.map fst (Buckets.bindings !buckets))
    in
    let buckets = ref Buckets.empty in
    Array.iteri (fun i key -> buckets := Buckets.add key i !buckets) bucket_keys;
    let b = Buffer.create 1024 in
    let token s =
      Buffer.add_string b (string_of_int (String.length s));
      Buffer.add_char b ':';
      Buffer.add_string b s
    in
    let integer n = token (string_of_int n) in
    let float x = token (Printf.sprintf "%016Lx" (Int64.bits_of_float x)) in
    let model = function
      | Bsm m ->
          token "bsm";
          float m.dividend_yield
      | Black76 -> token "black76"
      | Displaced d ->
          token "displaced";
          float d
      | Bachelier -> token "bachelier"
    in
    token convention;
    token snapshot_id;
    integer base_day;
    token
      (match day_count with
      | Actual_365_fixed -> "act365f"
      | Actual_360 -> "act360");
    token (Scenario.encoding scenarios);
    token
      (match output_mode with
      | Stream -> "stream"
      | Aggregate_only -> "aggregate-only");
    List.iter integer
      [
        limits.max_instruments;
        limits.max_scenarios;
        limits.max_calculations;
        limits.tile_rows;
        limits.max_workers;
        limits.max_buffered_results;
        limits.max_groups;
      ];
    integer (Array.length market);
    Array.iter
      (fun f ->
        token f.name;
        match f.market with
        | Spot_market m ->
            token "spot";
            float m.spot;
            float (Vol.to_float m.volatility)
        | Forward_market m ->
            token "forward";
            float m.forward;
            float (Vol.to_float m.volatility)
        | Normal_market m ->
            token "normal";
            float m.forward;
            float (Vol.to_float m.volatility))
      market;
    integer instruments;
    Array.iter
      (fun (p : position) ->
        token p.id;
        token p.factor;
        token p.rate_factor;
        token p.currency;
        float p.quantity;
        model p.model;
        float p.strike;
        integer p.expiry_day;
        float p.rate;
        token (match p.side with Side.Call -> "call" | Put -> "put"))
      portfolio;
    let outputs : type c. c output list -> unit =
     fun xs ->
      integer (List.length xs);
      List.iter
        (fun (Output (q, v)) ->
          token (quantity_name q);
          float (number q v))
        xs
    in
    if fast then token "fast-approximate-price"
    else (
      outputs lognormal_outputs;
      outputs normal_outputs);
    let plan_id =
      Digest.BLAKE256.to_hex (Digest.BLAKE256.string (Buffer.contents b))
    in
    Ok
      {
        assurance;
        portfolio;
        market;
        factor_indices;
        scenarios;
        base_day;
        day_count;
        lognormal_outputs;
        normal_outputs;
        output_mode;
        limits;
        explanation =
          {
            snapshot_id;
            kernels =
              (if fast then
                 Array.to_list portfolio
                 |> List.map (fun (p : position) ->
                        match p.model with
                        | Bsm _ -> "Black.Bsm.price"
                        | Black76 -> "Black.Black76.price"
                        | Displaced _ -> "Black.Displaced.price"
                        | Bachelier -> "Bachelier.price")
               else
                 Array.to_list bucket_keys
                 |> List.map (fun b ->
                        match b.model with
                        | Bsm _ -> "Production.Bsm"
                        | Black76 -> "Production.Black76"
                        | Displaced _ -> "Production.Displaced"
                        | Bachelier -> "Production.Bachelier"))
              |> List.sort_uniq String.compare;
            limits;
            output_mode;
            dependency_reuse =
              "frozen factor bindings; independent scalar requests";
            instruments;
            scenarios = scenario_count;
            calculations;
            tiles;
            raw_value_error_bytes;
            buffered_results;
            groups = Array.length bucket_keys;
            plan_id;
            convention;
          };
        buckets = !buckets;
        bucket_keys;
        tiles_per_scenario;
      }
  with Plan_error s -> Error s

let compile = compile_common ~assurance:Certified
let explain t = t.explanation

let manifest t =
  Printf.sprintf
    "planner-replay-v1\n\
     plan=%s\n\
     convention=%s\n\
     ocaml=%s\n\
     word-size=%d\n\
     snapshot=%S\n\
     numerical-mode=IEEE-binary64-explicit-fma-gradual-underflow\n"
    t.explanation.plan_id convention Sys.ocaml_version Sys.word_size
    t.explanation.snapshot_id

type tile = {
  id : int;
  scenario : int;
  first : int;
  length : int;
  plan_id : string;
}

let tile t id =
  if id < 0 || id >= t.explanation.tiles then invalid_arg "Planner.tile";
  let scenario = id / t.tiles_per_scenario
  and first = id mod t.tiles_per_scenario * t.limits.tile_rows in
  {
    id;
    scenario;
    first;
    length = min t.limits.tile_rows (t.explanation.instruments - first);
    plan_id = t.explanation.plan_id;
  }

type error = Post_expiry | Scalar of Production.error

type outcome =
  | Outcome :
      ('c, 'a) Production.quantity * ('a Production.certified, error) result
      -> outcome

type row = {
  scenario_id : int;
  instrument_index : int;
  instrument_id : string;
  factor_id : string;
  currency : string;
  coordinate : coordinate;
  outcomes : outcome list;
}

type prepared =
  | Expired
  | Prepared :
      ('i, 'c) Batch.model * 'i * ('c Vol.t, Refusal.t) result
      -> prepared

let prepare_position t point index =
  let p = t.portfolio.(index) in
  let m = t.market.(t.factor_indices.(index)).market in
  let days =
    Int64.sub
      (Int64.of_int p.expiry_day)
      (Int64.add (Int64.of_int t.base_day)
         (Int64.of_int point.Scenario.offset_days))
  in
  let time_to_expiry =
    Int64.to_float days
    /. match t.day_count with Actual_365_fixed -> 365. | Actual_360 -> 360.
  in
  let shock field base =
    List.fold_left
      (fun value s ->
        if s.Scenario.factor = p.factor && s.field = field then
          Scenario.apply s.adjustment base
        else value)
      base point.shocks
  in
  let prepare model inputs vol = Prepared (model, inputs, vol) in
  let prepared =
    match (p.model, m) with
    | Bsm b, Spot_market m ->
        prepare Batch.Bsm
          {
            Black.Bsm_carry.spot = shock Scenario.Spot m.spot;
            strike = p.strike;
            time_to_expiry;
            rate = p.rate;
            dividend_yield = b.dividend_yield;
          }
          (Vol.lognormal
             (shock Scenario.Lognormal_volatility (Vol.to_float m.volatility)))
    | Black76, Forward_market m ->
        prepare Batch.Black76
          {
            Black.Black76_carry.forward = shock Scenario.Forward m.forward;
            strike = p.strike;
            time_to_expiry;
            rate = p.rate;
          }
          (Vol.lognormal
             (shock Scenario.Lognormal_volatility (Vol.to_float m.volatility)))
    | Displaced displacement, Forward_market m ->
        prepare Batch.Displaced
          {
            Black.Displaced_carry.forward = shock Scenario.Forward m.forward;
            strike = p.strike;
            displacement;
            time_to_expiry;
            rate = p.rate;
          }
          (Vol.lognormal
             (shock Scenario.Lognormal_volatility (Vol.to_float m.volatility)))
    | Bachelier, Normal_market m ->
        prepare Batch.Bachelier
          {
            Bachelier.forward = shock Scenario.Forward m.forward;
            strike = p.strike;
            time_to_expiry;
            rate = p.rate;
          }
          (Vol.normal
             (shock Scenario.Normal_volatility (Vol.to_float m.volatility)))
    | _ -> assert false
  in
  if days < 0L then Expired else prepared

let evaluate_position t scenario_id point index =
  let p = t.portfolio.(index) in
  let outputs : type i c. (i, c) Batch.model -> c output list = function
    | Batch.Bachelier -> t.normal_outputs
    | Batch.Bsm -> t.lognormal_outputs
    | Batch.Black76 -> t.lognormal_outputs
    | Batch.Displaced -> t.lognormal_outputs
  in
  let failure outputs e =
    List.map (fun (Output (q, _)) -> Outcome (q, Error e)) outputs
  in
  let outcomes =
    match prepare_position t point index with
    | Expired -> (
        match p.model with
        | Bachelier -> failure t.normal_outputs Post_expiry
        | _ -> failure t.lognormal_outputs Post_expiry)
    | Prepared (model, inputs, vol) -> (
        let outputs = outputs model in
        match vol with
        | Error e -> failure outputs (Scalar (Production.Invalid_input e))
        | Ok sigma ->
            let requests =
              List.map
                (fun (Output (q, limit)) -> Production.Request (q, limit))
                outputs
            in
            List.map
              (fun (Production.Outcome (q, result)) ->
                Outcome (q, Result.map_error (fun e -> Scalar e) result))
              (Batch.evaluate_many model inputs p.side sigma requests))
  in
  {
    scenario_id;
    instrument_index = index;
    instrument_id = p.id;
    factor_id = p.factor;
    currency = p.currency;
    coordinate = coordinate p.model;
    outcomes;
  }

let evaluate_tile t work =
  if work.id < 0 || work.id >= t.explanation.tiles || work <> tile t work.id
  then Error "tile does not belong to plan"
  else
    let point = Scenario.point t.scenarios work.scenario in
    Ok
      (Array.init work.length (fun i ->
           evaluate_position t work.scenario point (work.first + i)))

type enclosed_total = { value : float; absolute_error : float }

type summary = {
  scenario_id : int;
  bucket : bucket;
  successful : int;
  failed : int;
  successful_subset : enclosed_total option;
  complete : bool;
}

type stop =
  | Complete
  | Cancelled
  | Sink_failure of string
  | Worker_failure of string

type completion = {
  stop : stop;
  rows_committed : int;
  calculations_committed : int;
}

type event = Row of row | Summary of summary | Finished of completion
type cancellation = bool Atomic.t

let cancellation () = Atomic.make false
let cancel c = Atomic.set c true

module E = Enclosure

(* Arithmetic state is exclusively owned by the coordinating domain. *)
type accumulator = {
  mutable successful : int;
  mutable failed : int;
  mutable sum : E.t option;
}

exception Stop of stop

let emit_to sink e =
  try
    match sink e with Ok () -> () | Error s -> raise (Stop (Sink_failure s))
  with
  | Stop _ as e -> raise e
  | e -> raise (Stop (Sink_failure (Printexc.to_string e)))

let run_waves ~max_workers ~tiles ~workers ~check_cancel ~run_tile ~accept =
  try
    if workers <= 0 || workers > max_workers then
      raise (Stop (Worker_failure "worker limit violated"));
    check_cancel ();
    let next = ref 0 in
    while !next < tiles do
      check_cancel ();
      let n = min workers (tiles - !next) in
      (* Spawned domains own their results. Joining every handle, even on an
         exception, is mandatory before returning or invoking a user sink. *)
      let handles = ref [] in
      let failure = ref None in
      for k = 1 to n - 1 do
        if Option.is_none !failure then
          try
            let id = !next + k in
            handles := Domain.spawn (fun () -> run_tile id) :: !handles
          with e -> failure := Some (Printexc.to_string e)
      done;
      let first =
        if Option.is_none !failure then run_tile !next else Error "spawn failed"
      in
      let rest =
        List.map
          (fun d -> try Domain.join d with e -> Error (Printexc.to_string e))
          (List.rev !handles)
      in
      (match !failure with
      | Some s -> raise (Stop (Worker_failure s))
      | None -> ());
      List.iter
        (function
          | Error s -> raise (Stop (Worker_failure s))
          | Ok rows -> Array.iter accept rows)
        (first :: rest);
      next := !next + n
    done;
    Complete
  with
  | Stop stop -> stop
  | e -> Worker_failure (Printexc.to_string e)

let execute t ~workers ~cancellation ~sink =
  let committed = ref 0 and calculations = ref 0 in
  let result stop =
    {
      stop;
      rows_committed = !committed;
      calculations_committed = !calculations;
    }
  in
  let emit = emit_to sink in
  let check_cancel () =
    if Atomic.get cancellation then raise (Stop Cancelled)
  in
  let states =
    Array.init (Array.length t.bucket_keys) (fun _ ->
        { successful = 0; failed = 0; sum = Some (E.exact 0.) })
  in
  let reset () =
    Array.iter
      (fun s ->
        s.successful <- 0;
        s.failed <- 0;
        s.sum <- Some (E.exact 0.))
      states
  in
  let summarize scenario_id =
    Array.iteri
      (fun i s ->
        let successful_subset =
          match s.sum with
          | None -> None
          | Some total -> (
              try
                let value = total.hi in
                let absolute_error = E.error_of_float total value in
                if Float.is_finite value && Float.is_finite absolute_error then
                  Some { value; absolute_error }
                else None
              with E.Unresolved _ -> None)
        in
        emit
          (Summary
             {
               scenario_id;
               bucket = t.bucket_keys.(i);
               successful = s.successful;
               failed = s.failed;
               successful_subset;
               complete = s.failed = 0 && Option.is_some successful_subset;
             }))
      states
  in
  let accept (row : row) =
    check_cancel ();
    let has_failure =
      List.exists (fun (Outcome (_, r)) -> Result.is_error r) row.outcomes
    in
    if t.output_mode = Stream || has_failure then emit (Row row);
    let p = t.portfolio.(row.instrument_index) in
    List.iter
      (fun (Outcome (q, r)) ->
        let s = states.(Buckets.find (bucket p (quantity_name q)) t.buckets) in
        match r with
        | Error _ -> s.failed <- s.failed + 1
        | Ok v ->
            s.successful <- s.successful + 1;
            s.sum <-
              (match s.sum with
              | None -> None
              | Some total -> (
                  try
                    Some
                      (E.add total
                         (E.mul_float
                            (E.add_error
                               (E.exact (number q v.value))
                               (number q v.absolute_error))
                            p.quantity))
                  with E.Unresolved _ -> None)))
      row.outcomes;
    incr committed;
    calculations := !calculations + List.length row.outcomes;
    if row.instrument_index = t.explanation.instruments - 1 then (
      summarize row.scenario_id;
      reset ())
  in
  let run_tile id =
    try evaluate_tile t (tile t id) with e -> Error (Printexc.to_string e)
  in
  let stop =
    run_waves ~max_workers:t.limits.max_workers ~tiles:t.explanation.tiles
      ~workers ~check_cancel ~run_tile ~accept
  in
  let completion = result stop in
  match stop with
  | Sink_failure _ -> completion
  | _ -> (
      try
        emit (Finished completion);
        completion
      with Stop stop -> result stop)

type plan = t
type plan_limits = limits

let plan_tile = tile

module Fast = struct
  type limits = {
    max_instruments : int;
    max_scenarios : int;
    max_calculations : int;
    tile_rows : int;
    max_workers : int;
    max_buffered_results : int;
  }

  type t = Plan of plan

  type explanation = {
    snapshot_id : string;
    kernels : string list;
    limits : limits;
    instruments : int;
    scenarios : int;
    calculations : int;
    tiles : int;
    raw_value_bytes : int;
    buffered_results : int;
    plan_id : string;
    convention : string;
  }

  let compile ~snapshot_id ~base_day ~day_count ~portfolio ~market ~scenarios
      ~(limits : limits) =
    let limits : plan_limits =
      {
        max_instruments = limits.max_instruments;
        max_scenarios = limits.max_scenarios;
        max_calculations = limits.max_calculations;
        tile_rows = limits.tile_rows;
        max_workers = limits.max_workers;
        max_buffered_results = limits.max_buffered_results;
        max_groups = 0;
      }
    in
    Result.map
      (fun p -> Plan p)
      (compile_common ~assurance:Fast_price ~snapshot_id ~base_day ~day_count
         ~portfolio ~market ~scenarios ~lognormal_outputs:[] ~normal_outputs:[]
         ~output_mode:Stream ~limits)

  let explain (Plan p) =
    let e = p.explanation in
    {
      snapshot_id = e.snapshot_id;
      kernels = e.kernels;
      limits =
        {
          max_instruments = p.limits.max_instruments;
          max_scenarios = p.limits.max_scenarios;
          max_calculations = p.limits.max_calculations;
          tile_rows = p.limits.tile_rows;
          max_workers = p.limits.max_workers;
          max_buffered_results = p.limits.max_buffered_results;
        };
      instruments = e.instruments;
      scenarios = e.scenarios;
      calculations = e.calculations;
      tiles = e.tiles;
      raw_value_bytes = e.raw_value_error_bytes;
      buffered_results = e.buffered_results;
      plan_id = e.plan_id;
      convention = e.convention;
    }

  let manifest (Plan p) =
    assert (p.assurance = Fast_price);
    Printf.sprintf
      "planner-fast-replay-v1\n\
       plan=%s\n\
       convention=%s\n\
       ocaml=%s\n\
       word-size=%d\n\
       snapshot=%S\n\
       assurance=fast-approximate\n\
       output=unweighted-price-stream\n\
       numerical-mode=IEEE-binary64-explicit-fma-gradual-underflow\n"
      p.explanation.plan_id p.explanation.convention Sys.ocaml_version
      Sys.word_size p.explanation.snapshot_id

  type tile = {
    id : int;
    scenario : int;
    first : int;
    length : int;
    plan_id : string;
  }

  let tile (Plan p) id =
    let t = plan_tile p id in
    {
      id = t.id;
      scenario = t.scenario;
      first = t.first;
      length = t.length;
      plan_id = t.plan_id;
    }

  type error = Post_expiry | Scalar of Batch.Fast.error

  type row = {
    scenario_id : int;
    instrument_index : int;
    instrument_id : string;
    factor_id : string;
    currency : string;
    coordinate : coordinate;
    quantity : float;
    price : (float, error) result;
  }

  let fast_request (position : position) model inputs sigma =
    Batch.Fast.Price (model, inputs, position.side, sigma)

  let make_row scenario_id index (position : position) price =
    {
      scenario_id;
      instrument_index = index;
      instrument_id = position.id;
      factor_id = position.factor;
      currency = position.currency;
      coordinate = coordinate position.model;
      quantity = position.quantity;
      price;
    }

  let evaluate_position p scenario_id point index =
    let position = p.portfolio.(index) in
    let price =
      match prepare_position p point index with
      | Expired -> Error Post_expiry
      | Prepared (model, inputs, vol) -> (
          match vol with
          | Error e -> Error (Scalar (Batch.Fast.Invalid_input e))
          | Ok sigma ->
              Result.map_error
                (fun e -> Scalar e)
                (Batch.Fast.evaluate (fast_request position model inputs sigma))
          )
    in
    make_row scenario_id index position price

  type tile_entry = Rejected of error | Price_request of Batch.Fast.request

  let evaluate_batch_tile p work point =
    let entries =
      Array.init work.length (fun i ->
          let index = work.first + i in
          let position = p.portfolio.(index) in
          match prepare_position p point index with
          | Expired -> Rejected Post_expiry
          | Prepared (model, inputs, vol) -> (
              match vol with
              | Error e -> Rejected (Scalar (Batch.Fast.Invalid_input e))
              | Ok sigma ->
                  Price_request (fast_request position model inputs sigma)))
    in
    let count = ref 0 and likely = ref 0 in
    Array.iter
      (function
        | Rejected _ -> ()
        | Price_request (Batch.Fast.Price (model, inputs, side, sigma)) ->
            incr count;
            let selected =
              match model with
              | Batch.Bachelier ->
                  Bachelier.Fast_middle.may_prepare inputs side sigma
              | _ -> false
            in
            if selected then incr likely)
      entries;
    let count = !count and likely = !likely in
    let make i price =
      let index = work.first + i in
      make_row work.scenario index p.portfolio.(index) price
    in
    if likely < 32 || likely < count - likely then
      Array.mapi
        (fun i entry ->
          make i
            (match entry with
            | Rejected e -> Error e
            | Price_request request ->
                Result.map_error
                  (fun e -> Scalar e)
                  (Batch.Fast.evaluate request)))
        entries
    else
      let cursor = ref 0 in
      let rec next_request () =
        let entry = entries.(!cursor) in
        incr cursor;
        match entry with Price_request r -> r | Rejected _ -> next_request ()
      in
      let requests = Array.init count (fun _ -> next_request ()) in
      let results = Batch.Fast.execute (Batch.Fast.compile requests) in
      let next = ref 0 in
      Array.mapi
        (fun i entry ->
          let price =
            match entry with
            | Rejected e -> Error e
            | Price_request _ ->
                let price =
                  Result.map_error (fun e -> Scalar e) results.(!next)
                in
                incr next;
                price
          in
          make i price)
        entries

  let evaluate_chunked_tile p work point =
    (* 256-word arrays fit the supported OCaml 5.3 minor-allocation limit.
       Bound preparation scratch independently of the caller's scheduling tile;
       the native SoA has at most 4*256 float words. *)
    let capacity = 256 in
    if work.length <= capacity then evaluate_batch_tile p work point
    else
      let first = evaluate_batch_tile p { work with length = capacity } point in
      let rows = Array.make work.length first.(0) in
      Array.blit first 0 rows 0 capacity;
      let offset = ref capacity in
      while !offset < work.length do
        let length = min capacity (work.length - !offset) in
        let chunk = { work with first = work.first + !offset; length } in
        let values =
          if length >= 32 then evaluate_batch_tile p chunk point
          else
            Array.init length (fun i ->
                evaluate_position p work.scenario point (chunk.first + i))
        in
        Array.blit values 0 rows !offset length;
        offset := !offset + length
      done;
      rows

  let batch_tile p work =
    (* Keep mixed-model and small tiles on their scalar streaming path. *)
    let rec homogeneous i =
      i = work.length
      || (p.portfolio.(work.first + i).model = Bachelier && homogeneous (i + 1))
    in
    Bachelier_native.default_enabled && work.length >= 32 && homogeneous 0

  let evaluate_tile_with ~batch (Plan p as plan) work =
    if
      work.id < 0 || work.id >= p.explanation.tiles || work <> tile plan work.id
    then Error "tile does not belong to fast plan"
    else
      let point = Scenario.point p.scenarios work.scenario in
      Ok
        (if batch && batch_tile p work then evaluate_chunked_tile p work point
         else
           Array.init work.length (fun i ->
               evaluate_position p work.scenario point (work.first + i)))

  let evaluate_tile plan work = evaluate_tile_with ~batch:true plan work

  type event = Row of row | Finished of completion

  let execute (Plan p as plan) ~workers ~cancellation ~sink =
    let committed = ref 0 in
    let result stop =
      { stop; rows_committed = !committed; calculations_committed = !committed }
    in
    let emit = emit_to sink in
    let check_cancel () =
      if Atomic.get cancellation then raise (Stop Cancelled)
    in
    let accept row =
      check_cancel ();
      emit (Row row);
      incr committed
    in
    let run_tile id =
      (* Fresh native preparation is qualified for serial execution. Preserve
         the scalar parallel path until its allocation/GC costs are qualified. *)
      try evaluate_tile_with ~batch:(workers = 1) plan (tile plan id)
      with e -> Error (Printexc.to_string e)
    in
    let stop =
      run_waves ~max_workers:p.limits.max_workers ~tiles:p.explanation.tiles
        ~workers ~check_cancel ~run_tile ~accept
    in
    let completion = result stop in
    match stop with
    | Sink_failure _ -> completion
    | _ -> (
        try
          emit (Finished completion);
          completion
        with Stop stop -> result stop)
end

module American = struct
  module A = Early_exercise.Bsm
  module B = Batch.American
  module C = Plan_encoding

  type 'a curve = { initial : 'a; changes : (int * 'a) array }

  type _ model =
    | Constant : {
        rate : float;
        dividend_yield : float;
        volatility : Vol.lognormal Vol.t;
      }
        -> B.constant model
    | Piecewise : {
        rate : float curve;
        dividend_yield : float curve;
        volatility : Vol.lognormal Vol.t curve;
      }
        -> B.piecewise model

  type instant = { day : int; side : A.event_side }

  type exercise =
    | American of { opening : instant; expiry_side : A.event_side }
    | Bermudan of instant array

  type dividend = { day : int; amount : float }

  type 'k specification = {
    id : string;
    factor : string;
    currency : string;
    quantity : float;
    strike : float;
    expiry_day : int;
    side : Side.t;
    model : 'k model;
    exercise : exercise;
    cash : dividend array option;
    outputs : 'k B.output list;
  }

  type position = Position : 'k specification -> position
  type factor = { name : string; spot : float }
  type cash_at_valuation = Before_payment | After_payment

  type limits = {
    max_instruments : int;
    max_market_factors : int;
    max_scenarios : int;
    max_calculations : int;
    tile_rows : int;
    max_workers : int;
    max_buffered_results : int;
    max_solver_workspace_bytes : int;
    max_schedule_events : int;
  }

  type explanation = {
    snapshot_id : string;
    plan_id : string;
    convention : string;
    limits : limits;
    instruments : int;
    scenarios : int;
    calculations : int;
    tiles : int;
    buffered_results : int;
    dependency_reuse : string;
  }

  type t = {
    portfolio : position array;
    market : factor array;
    factor_indices : int array;
    scenarios : Scenario.t;
    base_day : int;
    day_count : day_count;
    cash_at_valuation : cash_at_valuation;
    explanation : explanation;
    tiles_per_scenario : int;
    encoding : string;
  }

  type tile = {
    id : int;
    scenario : int;
    first : int;
    length : int;
    plan_id : string;
  }

  type error =
    | Post_expiry
    | Admission of A.input_error
    | Volatility of Refusal.t
    | Scalar of B.error

  type outcome =
    | Outcome : ('k, 'a) B.operation * ('a, error) result -> outcome

  type row = {
    scenario_id : int;
    instrument_index : int;
    instrument_id : string;
    factor_id : string;
    currency : string;
    quantity : float;
    outcomes : outcome list;
  }

  type event = Row of row | Finished of completion

  let convention =
    "american-planner-v1;frozen-spot;roll-fixed-events;parallel-level-volatility;typed-unweighted-stream"

  let valid_day d = d >= -1000000000 && d <= 1000000000
  let rank = function A.Regular | Before_cash -> 0 | After_cash -> 1

  let compare_instant (a : instant) (b : instant) =
    let k = Int.compare a.day b.day in
    if k <> 0 then k else Int.compare (rank a.side) (rank b.side)

  let expiry (p : 'k specification) =
    match p.exercise with
    | American x -> { day = p.expiry_day; side = x.expiry_side }
    | Bermudan a -> a.(Array.length a - 1)

  let event_side b = function
    | A.Regular -> C.token b "regular"
    | Before_cash -> C.token b "before"
    | After_cash -> C.token b "after"

  let encode_instant b (x : instant) =
    C.integer b x.day;
    event_side b x.side

  let encode_model : type k. C.t -> k model -> unit =
   fun b -> function
    | Constant m ->
        C.token b "constant";
        List.iter (C.float b)
          [ m.rate; m.dividend_yield; Vol.to_float m.volatility ]
    | Piecewise m ->
        C.token b "piecewise";
        let curve f c =
          f b c.initial;
          C.array
            (fun b (d, v) ->
              C.integer b d;
              f b v)
            b c.changes
        in
        curve C.float m.rate;
        curve C.float m.dividend_yield;
        curve (fun b x -> C.float b (Vol.to_float x)) m.volatility

  let copy_model : type k. k model -> k model = function
    | Constant _ as m -> m
    | Piecewise m ->
        let copy c = { c with changes = Array.copy c.changes } in
        Piecewise
          {
            rate = copy m.rate;
            dividend_yield = copy m.dividend_yield;
            volatility = copy m.volatility;
          }

  let copy_position (Position p) =
    Position
      {
        p with
        model = copy_model p.model;
        cash = Option.map Array.copy p.cash;
        exercise =
          (match p.exercise with
          | American _ as e -> e
          | Bermudan a -> Bermudan (Array.copy a));
      }

  let schedule_count (type k) (p : k specification) =
    let n = Option.fold ~none:0 ~some:Array.length p.cash in
    let n =
      sum n
        (match p.exercise with American _ -> 1 | Bermudan a -> Array.length a)
    in
    match p.model with
    | Constant _ -> n
    | Piecewise m ->
        List.fold_left sum n
          [
            Array.length m.rate.changes;
            Array.length m.dividend_yield.changes;
            Array.length m.volatility.changes;
          ]

  let check_schedule base (type k) (p : k specification) =
    require
      (valid_day p.expiry_day && p.expiry_day >= base)
      "expiry before base or invalid date";
    let cash = Option.value ~default:[||] p.cash in
    Array.iteri
      (fun i (d : dividend) ->
        require
          (d.day >= base && d.day <= p.expiry_day
          && (i = 0 || cash.(i - 1).day <= d.day))
          "cash dates out of order/range")
      cash;
    let at_cash day = Array.exists (fun (d : dividend) -> d.day = day) cash in
    let side (x : instant) =
      require
        (if at_cash x.day then x.side <> A.Regular else x.side = A.Regular)
        "event side does not match cash date"
    in
    (match p.exercise with
    | American e ->
        require
          (valid_day e.opening.day && e.opening.day <= p.expiry_day)
          "invalid opening date";
        side e.opening;
        side { day = p.expiry_day; side = e.expiry_side };
        require
          (compare_instant e.opening
             { day = p.expiry_day; side = e.expiry_side }
          <= 0)
          "opening after expiry instant"
    | Bermudan a ->
        require (Array.length a > 0) "empty exercise schedule";
        Array.iteri
          (fun i (x : instant) ->
            require
              (x.day >= base && x.day <= p.expiry_day
              && (i = 0 || compare_instant a.(i - 1) x < 0))
              "exercise dates out of order/range";
            side x)
          a;
        require
          (a.(Array.length a - 1).day = p.expiry_day)
          "missing expiry exercise");
    let curve c =
      Array.iteri
        (fun i (d, _) ->
          require
            (d > base && d < p.expiry_day
            && (i = 0 || fst c.changes.(i - 1) < d))
            "coefficient dates out of order/range")
        c.changes
    in
    match p.model with
    | Constant _ -> ()
    | Piecewise m ->
        curve m.rate;
        curve m.dividend_yield;
        curve m.volatility

  let prepare (type k) ~check ~base_day ~day_count ~cash_at_valuation ~spot
      (point : Scenario.point) (p : k specification) : (k B.model, error) result
      =
    let exception Invalid of error in
    let get f = function Ok x -> x | Error e -> raise (Invalid (f e)) in
    try
      check ();
      let day = base_day + point.offset_days in
      let cash = Option.value ~default:[||] p.cash in
      let on_cash = ref false in
      Array.iteri
        (fun i (d : dividend) ->
          if i land 255 = 0 then check ();
          if d.day = day then on_cash := true)
        cash;
      let side =
        if not !on_cash then A.Regular
        else
          match cash_at_valuation with
          | Before_payment -> A.Before_cash
          | After_payment -> A.After_cash
      in
      let now = { day; side } in
      if compare_instant now (expiry p) > 0 then raise (Invalid Post_expiry);
      let years d =
        float (d - day)
        /. match day_count with Actual_365_fixed -> 365. | Actual_360 -> 360.
      in
      let convert (x : instant) = A.{ time = years x.day; side = x.side } in
      let opening, dates =
        match p.exercise with
        | American e ->
            ( (if compare_instant e.opening now < 0 then now else e.opening),
              None )
        | Bermudan a ->
            let future =
              Array.to_list
                (Array.mapi
                   (fun i x ->
                     if i land 255 = 0 then check ();
                     x)
                   a)
              |> List.filter (fun x -> compare_instant x now >= 0)
              |> Array.of_list
            in
            if Array.length future = 0 then raise (Invalid Post_expiry);
            (future.(0), Some (Array.map convert future))
      in
      let cash =
        Option.map
          (fun a ->
            let ds =
              Array.to_list
                (Array.mapi
                   (fun i x ->
                     if i land 255 = 0 then check ();
                     x)
                   a)
              |> List.filter (fun (x : dividend) -> x.day >= day)
              |> List.map (fun (x : dividend) ->
                     A.{ time = years x.day; amount = x.amount })
              |> Array.of_list
            in
            A.
              {
                valuation_side = side;
                opening_side = opening.side;
                expiry_side = (expiry p).side;
                dividends = ds;
              })
          p.cash
      in
      let spot, vol_adjustment =
        List.fold_left
          (fun (s, v) (shock : Scenario.shock) ->
            if shock.factor <> p.factor then (s, v)
            else
              match shock.field with
              | Spot -> (Scenario.apply shock.adjustment s, v)
              | Lognormal_volatility -> (s, Some shock.adjustment)
              | Forward | Normal_volatility -> (s, v))
          (spot, None) point.shocks
      in
      let volatility x =
        match vol_adjustment with
        | None -> x
        | Some a ->
            get
              (fun e -> Volatility e)
              (Vol.lognormal (Scenario.apply a (Vol.to_float x)))
      in
      let t = years p.expiry_day and opens = years opening.day in
      let admit inputs =
        match (dates, cash) with
        | Some ds, _ -> A.admit_bermudan ?cash inputs ds
        | None, Some c -> A.admit_cash inputs c
        | None, None -> A.admit inputs
      in
      match p.model with
      | Constant m ->
          let inputs =
            A.
              {
                spot;
                strike = p.strike;
                rate = m.rate;
                dividend_yield = m.dividend_yield;
                time_to_expiry = t;
                opens_at = opens;
                volatility = volatility m.volatility;
              }
          in
          Ok (B.Constant (get (fun e -> Admission e) (admit inputs)))
      | Piecewise m ->
          let curve map c =
            let initial = ref c.initial and future = ref [] in
            Array.iteri
              (fun i (d, x) ->
                if i land 255 = 0 then check ();
                if d <= day then initial := x
                else future := (years d, map x) :: !future)
              c.changes;
            (map !initial, Array.of_list (List.rev !future))
          in
          let r, rs = curve Fun.id m.rate
          and q, qs = curve Fun.id m.dividend_yield
          and v, vs = curve volatility m.volatility in
          let get x = get (fun e -> Admission e) x in
          let inputs =
            A.Piecewise.
              {
                spot;
                strike = p.strike;
                rate = get (Rate.create ~horizon:t ~initial:r ~changes:rs);
                dividend_yield =
                  get (Yield.create ~horizon:t ~initial:q ~changes:qs);
                volatility =
                  get (Volatility.create ~horizon:t ~initial:v ~changes:vs);
                time_to_expiry = t;
                opens_at = opens;
              }
          in
          let a =
            match (dates, cash) with
            | Some ds, _ -> A.Piecewise.admit_bermudan ?cash inputs ds
            | None, Some c -> A.Piecewise.admit_cash inputs c
            | None, None -> A.Piecewise.admit inputs
          in
          Ok (B.Piecewise (get a))
    with Invalid e -> Error e

  let compile ~snapshot_id ~base_day ~day_count ~cash_at_valuation ~portfolio
      ~market ~scenarios ~(limits : limits) =
    try
      require
        (Sys.word_size = 64 && snapshot_id <> "" && valid_day base_day)
        "invalid snapshot/date";
      require
        (limits.max_market_factors >= 0
        && limits.max_instruments >= 0
        && limits.max_scenarios >= 0
        && limits.max_calculations >= 0
        && limits.tile_rows > 0 && limits.max_workers > 0
        && limits.max_buffered_results >= 0
        && limits.max_solver_workspace_bytes >= 0
        && limits.max_schedule_events >= 0)
        "invalid planner limits";
      let instruments = Array.length portfolio
      and scenario_count = Scenario.count scenarios in
      require
        (Array.length market <= limits.max_market_factors
        && instruments <= limits.max_instruments
        && scenario_count <= limits.max_scenarios)
        "dimension limit exceeded";
      Array.iter
        (fun (Position p) ->
          require
            (schedule_count p <= limits.max_schedule_events)
            "schedule event limit exceeded")
        portfolio;
      let portfolio = Array.map copy_position portfolio
      and market = Array.copy market in
      let factors = Hashtbl.create 16 and ids = Hashtbl.create 16 in
      Array.iteri
        (fun i f ->
          require
            (f.name <> "" && not (Hashtbl.mem factors f.name))
            "duplicate/empty factor";
          Hashtbl.add factors f.name i)
        market;
      List.iter
        (fun (factor, field) ->
          require (Hashtbl.mem factors factor) "unknown scenario factor";
          require
            (field = Scenario.Spot || field = Scenario.Lognormal_volatility)
            "unsupported American shock coordinate")
        (Scenario.bindings scenarios);
      let per_scenario = ref 0 and maximum_outputs = ref 0 in
      let factor_indices =
        Array.map
          (fun (Position p) ->
            require
              (p.id <> ""
              && (not (Hashtbl.mem ids p.id))
              && p.currency <> "" && Float.is_finite p.quantity)
              "invalid/duplicate position metadata";
            Hashtbl.add ids p.id ();
            let index =
              match Hashtbl.find_opt factors p.factor with
              | Some i -> i
              | None -> raise (Plan_error "unknown position factor")
            in
            check_schedule base_day p;
            (match
               prepare
                 ~check:(fun () -> ())
                 ~base_day ~day_count ~cash_at_valuation:Before_payment
                 ~spot:market.(index).spot
                 Scenario.{ offset_days = 0; shocks = [] }
                 p
             with
            | Ok _ -> ()
            | Error _ -> raise (Plan_error ("invalid original model: " ^ p.id)));
            let n = List.length p.outputs in
            per_scenario := sum !per_scenario n;
            maximum_outputs := max !maximum_outputs n;
            List.iter
              (fun o ->
                require
                  (B.output_workspace o <= limits.max_solver_workspace_bytes)
                  "solver workspace limit exceeded")
              p.outputs;
            index)
          portfolio
      in
      ignore (product scenario_count instruments);
      let calculations = product scenario_count !per_scenario in
      require
        (calculations <= limits.max_calculations)
        "calculation limit exceeded";
      let tiles_per_scenario =
        (instruments / limits.tile_rows)
        + if instruments mod limits.tile_rows = 0 then 0 else 1
      in
      let tiles = product scenario_count tiles_per_scenario in
      let buffered_results =
        product
          (product
             (min instruments limits.tile_rows)
             (min limits.max_workers tiles))
          (max 1 !maximum_outputs)
      in
      require
        (buffered_results <= limits.max_buffered_results)
        "in-flight output limit exceeded";
      let b = C.create () in
      C.token b convention;
      C.token b snapshot_id;
      C.integer b base_day;
      C.token b
        (match day_count with
        | Actual_365_fixed -> "act365f"
        | Actual_360 -> "act360");
      C.token b
        (match cash_at_valuation with
        | Before_payment -> "before"
        | After_payment -> "after");
      C.token b (Scenario.encoding scenarios);
      List.iter (C.integer b)
        [
          limits.max_instruments;
          limits.max_market_factors;
          limits.max_scenarios;
          limits.max_calculations;
          limits.tile_rows;
          limits.max_workers;
          limits.max_buffered_results;
          limits.max_solver_workspace_bytes;
          limits.max_schedule_events;
        ];
      C.array
        (fun b f ->
          C.token b f.name;
          C.float b f.spot)
        b market;
      C.array
        (fun b (Position p) ->
          List.iter (C.token b) [ p.id; p.factor; p.currency ];
          C.float b p.quantity;
          C.float b p.strike;
          C.integer b p.expiry_day;
          C.token b (match p.side with Side.Call -> "call" | Put -> "put");
          encode_model b p.model;
          (match p.exercise with
          | American e ->
              C.token b "american";
              encode_instant b e.opening;
              event_side b e.expiry_side
          | Bermudan a ->
              C.token b "bermudan";
              C.array encode_instant b a);
          C.option
            (C.array (fun b (d : dividend) ->
                 C.integer b d.day;
                 C.float b d.amount))
            b p.cash;
          C.integer b (List.length p.outputs);
          List.iter (fun o -> C.token b (B.output_encoding o)) p.outputs)
        b portfolio;
      let explanation =
        {
          snapshot_id;
          plan_id = C.digest b;
          convention;
          limits;
          instruments;
          scenarios = scenario_count;
          calculations;
          tiles;
          buffered_results;
          dependency_reuse =
            "frozen calendars/bindings; one admission per row; scalar-owned \
             grid/operator reuse; no cross-row values/factors";
        }
      in
      Ok
        {
          portfolio;
          market;
          factor_indices;
          scenarios;
          base_day;
          day_count;
          cash_at_valuation;
          explanation;
          tiles_per_scenario;
          encoding = C.contents b;
        }
    with Plan_error s -> Error s

  let explain t = t.explanation

  let manifest t =
    "american-plan-manifest-v1\nocaml=" ^ Sys.ocaml_version ^ "\nword-size="
    ^ string_of_int Sys.word_size
    ^ "\nplan=" ^ t.explanation.plan_id ^ "\n" ^ t.encoding

  let tile t id =
    if id < 0 || id >= t.explanation.tiles then
      invalid_arg "American tile index";
    let scenario = id / t.tiles_per_scenario
    and first = id mod t.tiles_per_scenario * t.explanation.limits.tile_rows in
    {
      id;
      scenario;
      first;
      length =
        min t.explanation.limits.tile_rows (t.explanation.instruments - first);
      plan_id = t.explanation.plan_id;
    }

  let evaluate_position t ~check scenario point index =
    check ();
    let (Position p) = t.portfolio.(index) in
    let outcomes =
      match
        prepare ~check ~base_day:t.base_day ~day_count:t.day_count
          ~cash_at_valuation:t.cash_at_valuation
          ~spot:t.market.(t.factor_indices.(index)).spot point p
      with
      | Error e ->
          List.map (fun (B.Output op) -> Outcome (op, Error e)) p.outputs
      | Ok model ->
          let r =
            B.evaluate
              ~cancel:(fun () ->
                check ();
                false)
              (B.Request
                 { id = p.id; model; side = p.side; outputs = p.outputs })
          in
          List.map
            (fun (B.Outcome (op, r)) ->
              Outcome (op, Result.map_error (fun e -> Scalar e) r))
            r.outcomes
    in
    check ();
    {
      scenario_id = scenario;
      instrument_index = index;
      instrument_id = p.id;
      factor_id = p.factor;
      currency = p.currency;
      quantity = p.quantity;
      outcomes;
    }

  let evaluate_tile_with t ~check work =
    if work.id < 0 || work.id >= t.explanation.tiles || work <> tile t work.id
    then Error "tile does not belong to American plan"
    else
      let point = Scenario.point t.scenarios work.scenario in
      Ok
        (Array.init work.length (fun i ->
             evaluate_position t ~check work.scenario point (work.first + i)))

  let evaluate_tile t work = evaluate_tile_with t ~check:(fun () -> ()) work

  let execute t ~workers ~cancellation ~sink =
    let committed = ref 0 and calculations = ref 0 in
    let result stop =
      {
        stop;
        rows_committed = !committed;
        calculations_committed = !calculations;
      }
    in
    let check_cancel () =
      if Atomic.get cancellation then raise (Stop Cancelled)
    in
    let accept (row : row) =
      check_cancel ();
      emit_to sink (Row row);
      incr committed;
      calculations := !calculations + List.length row.outcomes
    in
    let run_tile id =
      try evaluate_tile_with t ~check:check_cancel (tile t id) with
      | Stop Cancelled -> Ok [||]
      | e -> Error (Printexc.to_string e)
    in
    let stop =
      run_waves ~max_workers:t.explanation.limits.max_workers
        ~tiles:t.explanation.tiles ~workers ~check_cancel ~run_tile ~accept
    in
    let stop =
      match stop with
      | Complete when Atomic.get cancellation -> Cancelled
      | _ -> stop
    in
    let completion = result stop in
    match stop with
    | Sink_failure _ -> completion
    | _ -> (
        try
          emit_to sink (Finished completion);
          completion
        with Stop s -> result s)
end
