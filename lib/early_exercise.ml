module Bsm = struct
  type inputs = {
    spot : float;
    strike : float;
    rate : float;
    dividend_yield : float;
    time_to_expiry : float;
    opens_at : float;
    volatility : Vol.lognormal Vol.t;
  }

  type event_side = Regular | Before_cash | After_cash
  type dividend = { time : float; amount : float }

  type cash_specification = {
    valuation_side : event_side;
    opening_side : event_side;
    expiry_side : event_side;
    dividends : dividend array;
  }

  type exercise_instant = { time : float; side : event_side }

  type admitted =
    | Admitted of inputs
    | With_cash of inputs * cash_specification
    | Bermudan of inputs * cash_specification option * exercise_instant array

  type input_error = Invalid_input of string

  let admit p =
    let fields =
      [
        ("spot", p.spot, true);
        ("strike", p.strike, true);
        ("rate", p.rate, false);
        ("dividend_yield", p.dividend_yield, false);
        ("time_to_expiry", p.time_to_expiry, true);
        ("opens_at", p.opens_at, true);
      ]
    in
    match
      List.find_opt
        (fun (_, x, positive) ->
          (not (Float.is_finite x)) || (positive && x < 0.))
        fields
    with
    | Some (field, _, _) -> Error (Invalid_input field)
    | None when p.opens_at > p.time_to_expiry ->
        Error (Invalid_input "exercise window")
    | None -> Ok (Admitted p)

  let rank = function Regular -> 0 | Before_cash -> 1 | After_cash -> 2

  let admit_cash p cash =
    match admit p with
    | Error e -> Error e
    | Ok _ ->
        let previous = ref 0. and valid = ref true in
        Array.iter
          (fun (d : dividend) ->
            if
              (not (Float.is_finite d.time && Float.is_finite d.amount))
              || d.time < !previous || d.time > p.time_to_expiry
              || d.amount < 0.
            then valid := false;
            previous := d.time)
          cash.dividends;
        let event t =
          Array.exists (fun (d : dividend) -> d.time = t) cash.dividends
        in
        let phase t side = event t = (side <> Regular) in
        if not !valid then Error (Invalid_input "cash schedule")
        else if
          not
            (phase 0. cash.valuation_side
            && phase p.opens_at cash.opening_side
            && phase p.time_to_expiry cash.expiry_side)
        then Error (Invalid_input "cash event side")
        else if
          (p.opens_at = 0. && rank cash.valuation_side > rank cash.opening_side)
          || p.opens_at = p.time_to_expiry
             && rank cash.opening_side > rank cash.expiry_side
        then Error (Invalid_input "cash exercise instant ordering")
        else
          Ok
            (With_cash (p, { cash with dividends = Array.copy cash.dividends }))

  let admit_bermudan ?cash p dates =
    match match cash with None -> admit p | Some c -> admit_cash p c with
    | Error e -> Error e
    | Ok base ->
        let cash = match base with With_cash (_, c) -> Some c | _ -> None in
        let ds = match cash with None -> [||] | Some c -> c.dividends in
        let cursor = ref 0 and previous = ref None and valid = ref true in
        Array.iter
          (fun (e : exercise_instant) ->
            while !cursor < Array.length ds && ds.(!cursor).time < e.time do
              incr cursor
            done;
            let event =
              !cursor < Array.length ds && ds.(!cursor).time = e.time
            in
            if
              (not (Float.is_finite e.time))
              || e.time < 0. || e.time > p.time_to_expiry
              || event <> (e.side <> Regular)
            then valid := false;
            (match !previous with
            | Some before
              when before.time > e.time
                   || (before.time = e.time && rank before.side >= rank e.side)
              ->
                valid := false
            | _ -> ());
            previous := Some e)
          dates;
        let opening, expiry =
          match cash with
          | None -> (Regular, Regular)
          | Some c -> (c.opening_side, c.expiry_side)
        in
        if Array.length dates = 0 then
          Error (Invalid_input "empty Bermudan schedule")
        else if
          (not !valid)
          || dates.(0).time <> p.opens_at
          || dates.(0).side <> opening
          || dates.(Array.length dates - 1).time <> p.time_to_expiry
          || dates.(Array.length dates - 1).side <> expiry
        then Error (Invalid_input "Bermudan exercise instants")
        else
          Ok
            (Bermudan
               ( p,
                 cash,
                 Array.map
                   (fun e ->
                     { e with time = (if e.time = 0. then 0. else e.time) })
                   dates ))

  let inputs = function
    | Admitted p | With_cash (p, _) | Bermudan (p, _, _) -> p

  let cash_specification = function
    | Admitted _ | Bermudan (_, None, _) -> None
    | With_cash (_, cash) | Bermudan (_, Some cash, _) ->
        Some { cash with dividends = Array.copy cash.dividends }

  let exercise_schedule = function
    | Bermudan (_, _, dates) -> Some (Array.copy dates)
    | Admitted _ | With_cash _ -> None

  module Certified = struct
    type unsupported = Cash_specification | General_stopping

    type error =
      | Invalid_accuracy
      | Unsupported_capability of unsupported
      | Arithmetic_unresolved
      | Accuracy_exceeded
      | Cancelled

    type absolute_error_limit = float

    let absolute_error_limit x =
      if Float.is_finite x && x >= 0. then Ok x else Error Invalid_accuracy

    type reduction = Expiry | Terminal_only | No_early_exercise_call

    type price = {
      value : float;
      absolute_error : float;
      reduction : reduction;
    }

    let reduction admitted side =
      match admitted with
      | With_cash _ | Bermudan (_, Some _, _) ->
          Error (Unsupported_capability Cash_specification)
      | Admitted p | Bermudan (p, None, _) ->
          if p.time_to_expiry = 0. then Ok Expiry
          else if p.opens_at = p.time_to_expiry then Ok Terminal_only
          else if side = Side.Call && p.dividend_yield = 0. && p.rate >= 0. then
            Ok No_early_exercise_call
          else Error (Unsupported_capability General_stopping)

    let accept reduction ~max_error value absolute_error =
      if
        not
          (Float.is_finite value
          && Float.is_finite absolute_error
          && absolute_error >= 0.)
      then Error Arithmetic_unresolved
      else if absolute_error > max_error then Error Accuracy_exceeded
      else Ok { value; absolute_error; reduction }

    let boundary p side =
      let module E = Enclosure in
      if p.time_to_expiry = 0. then
        let x =
          if side = Side.Call then E.sub (E.exact p.spot) (E.exact p.strike)
          else E.sub (E.exact p.strike) (E.exact p.spot)
        in
        match E.sign x with
        | E.Positive -> x
        | E.Zero | E.Negative -> E.exact 0.
        | E.Indeterminate -> raise (E.Unresolved "reduction payoff sign")
      else if
        (p.spot = 0. && side = Side.Call) || (p.strike = 0. && side = Side.Put)
      then E.exact 0.
      else
        let amount, rate =
          if p.spot = 0. then (p.strike, p.rate) else (p.spot, p.dividend_yield)
        in
        E.mul (E.exact amount)
          (E.exp (E.mul (E.exact (-.rate)) (E.exact p.time_to_expiry)))

    let price ?(cancel = fun () -> false) admitted side ~max_error =
      if cancel () then Error Cancelled
      else
        match reduction admitted side with
        | Error e -> Error e
        | Ok reduction ->
            let p = inputs admitted in
            let result =
              if p.time_to_expiry = 0. || p.spot = 0. || p.strike = 0. then
                try
                  let x = boundary p side in
                  accept reduction ~max_error x.hi
                    (Enclosure.error_of_float x x.hi)
                with Enclosure.Unresolved _ -> Error Arithmetic_unresolved
              else
                let original : Black.Bsm.inputs =
                  {
                    spot = p.spot;
                    strike = p.strike;
                    rate = p.rate;
                    dividend_yield = p.dividend_yield;
                    time_to_expiry = p.time_to_expiry;
                  }
                in
                match Production.Bsm.admit original with
                | Error _ -> Error Arithmetic_unresolved
                | Ok european -> (
                    match
                      Production.Bsm.evaluate european side p.volatility
                        Production.Price ~max_error
                    with
                    | Ok certificate ->
                        accept reduction ~max_error certificate.value
                          certificate.absolute_error
                    | Error Production.Accuracy_exceeded ->
                        Error Accuracy_exceeded
                    | Error Production.Invalid_accuracy ->
                        Error Invalid_accuracy
                    | Error
                        ( Production.Invalid_input _ | Production.Unsupported _
                        | Production.Numerical_failure ) ->
                        Error Arithmetic_unresolved)
            in
            if cancel () then Error Cancelled else result
  end

  let eligible p cash t side =
    (t > p.opens_at || (t = p.opens_at && rank side >= rank cash.opening_side))
    && (t < p.time_to_expiry
       || (t = p.time_to_expiry && rank side <= rank cash.expiry_side))

  let active_jump p cash t =
    (not (t = 0. && cash.valuation_side = After_cash))
    && not (t = p.time_to_expiry && cash.expiry_side = Before_cash)

  type limits = {
    max_nodes : int;
    max_steps : int;
    max_policy_solves : int;
    max_row_visits : int;
    max_workspace_bytes : int;
    policy_iterations : int;
  }

  type configuration = {
    tolerance : float;
    space_cells : int;
    time_steps : int;
    domain_expansions : int;
    limits : limits;
  }

  let configure ~tolerance ~space_cells ~time_steps ~domain_expansions ~limits =
    if (not (Float.is_finite tolerance)) || tolerance <= 0. then
      Error "positive finite tolerance required"
    else if
      space_cells < 4
      || space_cells > max_int / 16
      || time_steps < 1
      || time_steps > max_int / 16
    then Error "invalid space/time counts"
    else if domain_expansions < 2 || domain_expansions > 16 then
      Error "domain_expansions must be in [2,16]"
    else if
      limits.max_nodes < 3
      || limits.max_nodes > min Sys.max_array_length (max_int / 1024)
      || limits.max_steps < 1
      || limits.max_policy_solves < 1
      || limits.max_row_visits < 1
      || limits.max_workspace_bytes < 1
      || limits.policy_iterations < 1
      || limits.policy_iterations > max_int / 128
    then Error "invalid resource limits"
    else Ok { tolerance; space_cells; time_steps; domain_expansions; limits }

  type refinement = {
    space_changes : float * float;
    time_changes : float * float;
    domain_changes : float * float;
    event_changes : (float * float) option;
    boundary_half_spread : float;
    observed_sum : float;
  }

  type failure =
    | Resource_limit of string
    | Cancelled
    | Arithmetic_unresolved of string
    | Unrepresentable
    | Nonconvergence of { step : int; row : int; residual : float }
    | Accuracy_not_demonstrated of refinement

  type work = {
    steps : int;
    policy_solves : int;
    row_visits : int;
    largest_grid : int;
    final_nodes : int;
    final_upper_stock : float;
    finest_steps_per_slab : int;
    domain_expansions : int;
    switched_rows : int;
  }

  type region_kind = Estimated_exercise | Estimated_continuation | Unresolved
  type region = { lower_stock : float; upper_stock : float; kind : region_kind }
  type 'a diagnostic = Not_requested | Unavailable of string | Available of 'a

  type premium = {
    value : float;
    european_value : float;
    european_absolute_error : float;
    subtraction_indicator : float;
  }

  type mapping = {
    event_applications : int;
    maximum_cell_width : float;
    arithmetic_indicator : float;
  }

  type assurance = Estimated_only

  type estimated_price = {
    value : float;
    assurance : assurance;
    method_name : string;
    requested_tolerance : float;
    refinement : refinement option;
    mapping : mapping option;
    maximum_residual : float;
    maximum_roundoff_indicator : float;
    boundary_arithmetic_indicator : float;
    work : work;
    exercise_regions : region list diagnostic;
    early_exercise_premium : premium diagnostic;
  }

  exception Stop of failure

  let fail s = raise (Stop (Arithmetic_unresolved s))

  let[@inline always] finite s x =
    if not (Float.is_finite x) then fail s;
    x

  let[@inline always] nonnegative s x =
    let x = finite s x in
    if x < 0. then fail s;
    x

  (* Match Stdlib's operand selection (including equal signed zeros and NaN),
     with float-specific comparisons so hot row loops need no boxed operands.
     Finite-value checks remain at their original call sites. *)
  let[@inline always] float_max (a : float) (b : float) =
    if a >= b then a else b

  let[@inline always] float_min (a : float) (b : float) =
    if a <= b then a else b

  module E = Enclosure.Fast

  let centre (x : E.t) = x.hi +. x.lo +. (x.third +. x.fourth)
  let exact = E.exact

  let positive_part x =
    match E.sign x with
    | E.Positive -> x
    | E.Zero | E.Negative -> exact 0.
    | E.Indeterminate -> fail "payoff sign unresolved"

  let payoff_e side s k =
    positive_part
      (match side with Side.Call -> E.sub s k | Side.Put -> E.sub k s)

  let enclosed x =
    let v = finite "enclosed value" (centre x) in
    let error =
      nonnegative "enclosed arithmetic error" (E.error_of_float x v)
    in
    (v, error)

  let exp_product a t = E.exp (E.mul (exact a) t)

  let terminal p side t =
    payoff_e side
      (E.mul (exact p.spot) (exp_product (-.p.dividend_yield) t))
      (E.mul (exact p.strike) (exp_product (-.p.rate) t))

  let european p side =
    let m =
      Model_enclosure.Fast.black ~spot:p.spot ~spot_low:0. ~strike:p.strike
        ~strike_low:0. ~time:p.time_to_expiry ~rate:p.rate
        ~yield:p.dividend_yield
    in
    enclosed (Model_enclosure.Fast.price m side (Vol.to_float p.volatility))

  let analytic p side =
    let t = p.time_to_expiry in
    if t = 0. then
      Some ("expiry", enclosed (payoff_e side (exact p.spot) (exact p.strike)))
    else if p.spot = 0. then
      Some
        ( "absorbing-stock",
          if side = Side.Call then (0., 0.)
          else
            enclosed
              (E.mul (exact p.strike)
                 (exp_product (-.p.rate)
                    (exact (if p.rate < 0. then t else p.opens_at)))) )
    else if p.strike = 0. then
      Some
        ( "zero-strike",
          if side = Side.Put then (0., 0.)
          else
            enclosed
              (E.mul (exact p.spot)
                 (exp_product (-.p.dividend_yield)
                    (exact (if p.dividend_yield < 0. then t else p.opens_at))))
        )
    else if Vol.to_float p.volatility = 0. then (
      let best = ref (enclosed (terminal p side (exact p.opens_at))) in
      let add t =
        let v, e = enclosed (terminal p side t) in
        let bv, be = !best in
        best := (float_max bv v, float_max be e)
      in
      add (exact t);
      (if
         p.rate <> 0. && p.dividend_yield <> 0.
         && p.rate > 0. = (p.dividend_yield > 0.)
         && p.rate <> p.dividend_yield
       then
         (* log(|r| K / (|q| S)) / (r-q), without overflowing the ratio. *)
         let log_ratio =
           E.sub
             (E.add (E.log (exact (abs_float p.rate))) (E.log (exact p.strike)))
             (E.add
                (E.log (exact (abs_float p.dividend_yield)))
                (E.log (exact p.spot)))
         in
         let root =
           E.div log_ratio (E.sub (exact p.rate) (exact p.dividend_yield))
         in
         match (E.compare_float root p.opens_at, E.compare_float root t) with
         | E.Positive, E.Negative -> add root
         | E.Negative, _ | _, E.Positive | E.Zero, _ | _, E.Zero -> ()
         | _ -> fail "stationary time overlaps exercise endpoint");
      Some ("deterministic-stopping", !best))
    else if
      p.opens_at = t
      || (side = Side.Call && p.dividend_yield = 0. && p.rate >= 0.)
    then Some ("European-reduction", european p side)
    else None

  (* Coincident amounts are added as original-word enclosures before any
     subtraction. A numeric failure is not invalid financial admission. *)
  let prepare_cash cfg cancel visits cash =
    let count = Array.length cash.dividends in
    let budget = cfg.limits.max_workspace_bytes in
    if
      count > cfg.limits.max_row_visits || count > max 0 (budget - 65536) / 1024
    then raise (Stop (Resource_limit "cash metadata"));
    let events = ref [] in
    Array.iteri
      (fun i (d : dividend) ->
        incr visits;
        if i land 255 = 0 && cancel () then raise (Stop Cancelled);
        match !events with
        | (time, amount) :: tail when time = d.time ->
            events := (time, E.add amount (exact d.amount)) :: tail
        | _ -> events := (d.time, exact d.amount) :: !events)
      cash.dividends;
    List.rev !events

  let cash_analytic cfg cancel visits p cash events side =
    let sigma = Vol.to_float p.volatility in
    if p.spot = 0. || (p.strike = 0. && side = Side.Put) then analytic p side
    else if sigma <> 0. && p.time_to_expiry <> 0. then None
    else
      let best = ref (0., 0.)
      and stock = ref (exact p.spot)
      and previous = ref 0. in
      let tick () =
        incr visits;
        if !visits > cfg.limits.max_row_visits then
          raise (Stop (Resource_limit "deterministic cash visits"));
        if cancel () then raise (Stop Cancelled)
      in
      let add time state =
        tick ();
        let value, error =
          enclosed
            (E.mul
               (exp_product (-.p.rate) time)
               (payoff_e side state (exact p.strike)))
        in
        best := (float_max value (fst !best), float_max error (snd !best))
      in
      let segment time =
        tick ();
        if time > !previous then (
          let start = !previous and initial = !stock in
          let state t =
            E.mul initial
              (E.exp
                 (E.mul
                    (E.sub (exact p.rate) (exact p.dividend_yield))
                    (E.sub t (exact start))))
          in
          let lo = float_max start p.opens_at in
          (* Open intervals have the same supremum at a limiting endpoint.
             A zero-length interval confers no additional exercise right. *)
          if lo < time then (
            add (exact lo) (state (exact lo));
            add (exact time) (state (exact time));
            if
              p.rate <> 0. && p.dividend_yield <> 0.
              && p.rate > 0. = (p.dividend_yield > 0.)
              && p.rate <> p.dividend_yield && p.strike > 0.
            then
              let positive =
                match E.sign initial with
                | E.Positive -> true
                | E.Zero -> false
                | E.Negative | E.Indeterminate ->
                    fail "cash stationary stock sign unresolved"
              in
              if positive then
                let ratio =
                  E.sub
                    (E.add
                       (E.log (exact (abs_float p.rate)))
                       (E.log (exact p.strike)))
                    (E.add
                       (E.log (exact (abs_float p.dividend_yield)))
                       (E.log initial))
                in
                let stationary =
                  E.add (exact start)
                    (E.div ratio
                       (E.sub (exact p.rate) (exact p.dividend_yield)))
                in
                match
                  ( E.compare_float stationary lo,
                    E.compare_float stationary time )
                with
                | E.Positive, E.Negative -> add stationary (state stationary)
                | E.Indeterminate, _ | _, E.Indeterminate ->
                    fail "cash stationary endpoint unresolved"
                | _ -> ());
          stock := state (exact time));
        previous := time
      in
      List.iter
        (fun (time, amount) ->
          segment time;
          if active_jump p cash time then (
            if eligible p cash time Before_cash then add (exact time) !stock;
            stock := positive_part (E.sub !stock amount);
            if eligible p cash time After_cash then add (exact time) !stock))
        events;
      segment p.time_to_expiry;
      if eligible p cash p.time_to_expiry cash.expiry_side then
        add (exact p.time_to_expiry) !stock;
      Some ("cash-deterministic-stopping", !best)

  (* Merge already admitted orders; neither sorting nor solver steps add rights. *)
  let prepare_bermudan cfg cancel visits dates events cash_count =
    let count = Array.length dates in
    if
      count > cfg.limits.max_row_visits - !visits
      || count
         > (max 0 (cfg.limits.max_workspace_bytes - 65536) / 1024) - cash_count
    then raise (Stop (Resource_limit "Bermudan metadata"));
    let i = ref 0 and pending = ref events and result = ref [] in
    while !i < count || !pending <> [] do
      if cancel () then raise (Stop Cancelled);
      let next = if !i < count then dates.(!i).time else infinity in
      let time =
        match !pending with (t, _) :: _ -> float_min t next | [] -> next
      in
      let amount =
        match !pending with
        | (t, a) :: tail when t = time ->
            pending := tail;
            Some a
        | _ -> None
      in
      let regular = ref false and before = ref false and after = ref false in
      while !i < count && dates.(!i).time = time do
        incr visits;
        (match dates.(!i).side with
        | Regular -> regular := true
        | Before_cash -> before := true
        | After_cash -> after := true);
        incr i
      done;
      result := (time, amount, !regular, !before, !after) :: !result
    done;
    List.rev !result

  let bermudan_analytic cfg cancel visits p cash timeline side =
    if p.spot = 0. || (p.strike = 0. && side = Side.Put) then analytic p side
    else if
      cash = None
      && (p.strike = 0.
         || p.opens_at = p.time_to_expiry
         || (side = Side.Call && p.dividend_yield = 0. && p.rate >= 0.))
    then analytic p side
    else if
      p.spot <> 0.
      && (not (p.strike = 0. && side = Side.Put))
      && Vol.to_float p.volatility <> 0.
      && p.time_to_expiry <> 0.
    then None
    else
      let best = ref (0., 0.)
      and stock = ref (exact p.spot)
      and previous = ref 0. in
      let tick () =
        incr visits;
        if !visits > cfg.limits.max_row_visits then
          raise (Stop (Resource_limit "Bermudan deterministic visits"));
        if cancel () then raise (Stop Cancelled)
      in
      let add t =
        tick ();
        let value, error =
          enclosed
            (E.mul
               (exp_product (-.p.rate) (exact t))
               (payoff_e side !stock (exact p.strike)))
        in
        best := (float_max value (fst !best), float_max error (snd !best))
      in
      List.iter
        (fun (t, amount, regular, before, after) ->
          tick ();
          if t > !previous && E.sign !stock <> E.Zero then
            stock :=
              E.mul !stock
                (E.exp
                   (E.mul
                      (E.sub (exact p.rate) (exact p.dividend_yield))
                      (E.sub (exact t) (exact !previous))));
          if regular || before then add t;
          (match (amount, cash) with
          | Some a, Some spec when active_jump p spec t ->
              stock := positive_part (E.sub !stock a)
          | _ -> ());
          if after then add t;
          previous := t)
        timeline;
      Some ("Bermudan-deterministic-stopping", !best)

  (* Curves keep the declared partition for getters and a validated coalesced
     partition for execution. Coalescing never repairs invalid input. *)
  type curve = {
    horizon : float;
    initial : float;
    changes : (float * float) array;
    segments : (float * float) array;
  }

  type coefficient_curves = {
    rates : curve;
    yields : curve;
    vols : curve;
    knots : float list;
  }

  let make_curve ~horizon ~initial ~changes =
    let previous = ref 0. in
    let valid =
      ref (Float.is_finite horizon && horizon >= 0. && Float.is_finite initial)
    in
    Array.iter
      (fun (time, value) ->
        if
          (not (Float.is_finite time && Float.is_finite value))
          || time <= !previous || time >= horizon
        then valid := false;
        previous := time)
      changes;
    if not !valid then
      Error (Invalid_input "coefficient horizon, level or partition")
    else
      let levels = ref [ (0., initial) ] and last = ref initial in
      Array.iter
        (fun (t, v) ->
          if v <> !last then (
            levels := (t, v) :: !levels;
            last := v))
        changes;
      Ok
        {
          horizon;
          initial;
          changes = Array.copy changes;
          segments = Array.of_list (List.rev !levels);
        }

  let curve_index curve t =
    let lo = ref 0 and hi = ref (Array.length curve.segments) in
    while !hi - !lo > 1 do
      let m = !lo + ((!hi - !lo) / 2) in
      if fst curve.segments.(m) <= t then lo := m else hi := m
    done;
    !lo

  let curve_level curve t = snd curve.segments.(curve_index curve t)

  let curve_integral tick curve a b transform =
    let result = ref (exact 0.) and previous = ref a in
    let i = ref (curve_index curve a) in
    while !previous < b do
      tick ();
      let next =
        if !i + 1 < Array.length curve.segments then
          float_min b (fst curve.segments.(!i + 1))
        else b
      in
      result :=
        E.add !result
          (E.mul
             (transform (snd curve.segments.(!i)))
             (E.sub (exact next) (exact !previous)));
      previous := next;
      incr i
    done;
    !result

  let maximum_enclosure a b =
    match E.sign (E.sub a b) with
    | E.Positive | E.Zero -> a
    | E.Negative -> b
    | E.Indeterminate ->
        let av, ae = enclosed a and bv, be = enclosed b in
        E.add_error (exact (float_max av bv)) (float_max ae be)

  (* Discount optimality depends on all future permitted times, never just
     the sign of the current segment. Piecewise linear integrals attain
     their extrema at window endpoints/knots, or listed finite rights. *)
  let discount_optimum tick curve dates p from =
    let best = ref None in
    let add t =
      tick ();
      if t >= from && t >= p.opens_at then
        let value = E.neg (curve_integral tick curve from t exact) in
        best :=
          Some
            (match !best with
            | None -> value
            | Some b -> maximum_enclosure b value)
    in
    (match dates with
    | Some ds -> Array.iter (fun (e : exercise_instant) -> add e.time) ds
    | None ->
        add (float_max from p.opens_at);
        add p.time_to_expiry;
        Array.iter (fun (t, _) -> add t) curve.segments);
    match !best with
    | Some x -> x
    | None -> fail "missing future exercise instant"

  let piecewise_european tick curves p side =
    let integral curve f = curve_integral tick curve 0. p.time_to_expiry f in
    let x = E.mul (exact p.spot) (E.exp (E.neg (integral curves.yields exact)))
    and y = E.mul (exact p.strike) (E.exp (E.neg (integral curves.rates exact)))
    and variance = integral curves.vols (fun v -> E.mul (exact v) (exact v)) in
    if p.spot = 0. || p.strike = 0. || E.sign variance = E.Zero then
      enclosed (payoff_e side x y)
    else
      let root = E.sqrt variance in
      let d1 =
        E.div
          (E.add (E.sub (E.log x) (E.log y)) (E.mul_float variance 0.5))
          root
      in
      let d2 = E.sub d1 root and cdf = Model_enclosure.Fast.cdf in
      enclosed
        (positive_part
           (match side with
           | Side.Call -> E.sub (E.mul x (cdf d1)) (E.mul y (cdf d2))
           | Side.Put ->
               E.sub (E.mul y (cdf (E.neg d2))) (E.mul x (cdf (E.neg d1)))))

  let piecewise_analytic tick curves p cash events dates side =
    if p.spot = 0. || (p.strike = 0. && side = Side.Put) then
      Some
        ( "piecewise-absorbing-stock",
          if side = Side.Call || p.strike = 0. then (0., 0.)
          else
            enclosed
              (E.mul (exact p.strike)
                 (E.exp (discount_optimum tick curves.rates dates p 0.))) )
    else if p.strike = 0. && cash = None then
      Some
        ( "piecewise-zero-strike",
          enclosed
            (E.mul (exact p.spot)
               (E.exp (discount_optimum tick curves.yields dates p 0.))) )
    else if
      p.time_to_expiry = 0.
      || Array.for_all (fun (_, v) -> v = 0.) curves.vols.segments
    then (
      let permitted t phase =
        match dates with
        | Some ds ->
            Array.exists
              (fun (e : exercise_instant) ->
                tick ();
                e.time = t && e.side = phase)
              ds
        | None -> (
            match cash with
            | None -> t >= p.opens_at
            | Some spec -> eligible p spec t phase)
      in
      let times =
        List.sort_uniq Float.compare
          ((0. :: p.opens_at :: p.time_to_expiry :: curves.knots)
          @ List.map fst events
          @
          match dates with
          | None -> []
          | Some ds ->
              Array.to_list
                (Array.map (fun (e : exercise_instant) -> e.time) ds))
      in
      let stock = ref (exact p.spot)
      and discount = ref (exact 1.)
      and previous = ref 0. in
      let best = ref (exact 0.) in
      let add d s =
        tick ();
        best :=
          maximum_enclosure !best (E.mul d (payoff_e side s (exact p.strike)))
      in
      let pending = ref events in
      List.iter
        (fun t ->
          tick ();
          let a = !previous in
          if a < t then (
            let r = curve_level curves.rates a
            and q = curve_level curves.yields a in
            let drift = E.sub (exact r) (exact q) in
            let at elapsed = E.mul !stock (E.exp (E.mul drift elapsed)) in
            let disc elapsed = E.mul !discount (exp_product (-.r) elapsed) in
            let width = E.sub (exact t) (exact a) in
            if dates = None && a >= p.opens_at then (
              add !discount !stock;
              add (disc width) (at width);
              if
                r <> 0. && q <> 0.
                && r > 0. = (q > 0.)
                && r <> q && p.strike > 0.
              then
                match E.sign !stock with
                | E.Zero -> ()
                | E.Positive -> (
                    let ratio =
                      E.sub
                        (E.add
                           (E.log (exact (abs_float r)))
                           (E.log (exact p.strike)))
                        (E.add (E.log (exact (abs_float q))) (E.log !stock))
                    in
                    let root = E.div ratio drift in
                    match (E.sign root, E.sign (E.sub root width)) with
                    | E.Positive, E.Negative -> add (disc root) (at root)
                    | E.Indeterminate, _ | _, E.Indeterminate ->
                        fail "piecewise stationary endpoint unresolved"
                    | _ -> ())
                | _ -> fail "piecewise deterministic stock sign");
            stock := at width;
            discount := disc width);
          let event =
            match !pending with
            | (u, amount) :: tail when u = t ->
                pending := tail;
                Some amount
            | _ -> None
          in
          let phase =
            match (event, cash) with
            | Some _, Some spec when t = 0. -> spec.valuation_side
            | Some _, _ -> Before_cash
            | None, _ -> Regular
          in
          if permitted t phase then add !discount !stock;
          (match (event, cash) with
          | Some amount, Some spec when active_jump p spec t ->
              stock := positive_part (E.sub !stock amount);
              if permitted t After_cash then add !discount !stock
          | _ -> ());
          previous := t)
        times;
      Some ("piecewise-deterministic-stopping", enclosed !best))
    else if
      cash = None
      && (p.opens_at = p.time_to_expiry
         || side = Side.Call
            && Array.for_all (fun (_, v) -> v = 0.) curves.yields.segments
            && Array.for_all (fun (_, v) -> v >= 0.) curves.rates.segments)
    then
      Some
        ("piecewise-European-reduction", piecewise_european tick curves p side)
    else None

  type context = {
    cfg : configuration;
    cancel : unit -> bool;
    mutable steps : int;
    mutable policies : int;
    mutable visits : int;
    mutable largest : int;
    mutable switched : int;
    mutable residual : float;
    mutable roundoff : float;
    mutable boundary_error : float;
    mutable event_applications : int;
    mutable mapping_width : float;
    mutable mapping_error : float;
    local : float;
  }

  let check c = if c.cancel () then raise (Stop Cancelled)

  let[@inline always] tick c =
    if c.visits >= c.cfg.limits.max_row_visits then
      raise (Stop (Resource_limit "row visits"));
    c.visits <- c.visits + 1;
    if c.visits land 255 = 0 then check c

  let step c =
    check c;
    if c.steps >= c.cfg.limits.max_steps then
      raise (Stop (Resource_limit "time steps"));
    c.steps <- c.steps + 1

  let policy c =
    check c;
    if c.policies >= c.cfg.limits.max_policy_solves then
      raise (Stop (Resource_limit "policy solves"));
    c.policies <- c.policies + 1

  let accept_boundary c v e =
    c.boundary_error <- float_max c.boundary_error e;
    if e > c.local then fail "boundary arithmetic resolution";
    nonnegative "boundary value" v

  let boundary c x =
    let v, e = enclosed x in
    accept_boundary c v e

  let check_workspace c =
    (* Includes grids, 24 float bands/vectors, policy flags, retained fine pair,
       optional region records, and bounded enclosure temporaries. *)
    let budget = c.cfg.limits.max_workspace_bytes in
    let policy_bytes = 32 * c.cfg.limits.policy_iterations in
    if
      budget < 65536
      || policy_bytes > budget - 65536
      || c.cfg.limits.max_nodes > (budget - 65536 - policy_bytes) / 512
    then raise (Stop (Resource_limit "workspace bytes"))

  let grid c p level domain =
    check c;
    let capacity = c.cfg.limits.max_nodes in
    let x = Array.make capacity 0. in
    let n = ref 0 in
    let append v =
      tick c;
      if !n = capacity then raise (Stop (Resource_limit "grid nodes"));
      if not (Float.is_finite v) then raise (Stop Unrepresentable);
      if !n > 0 && v <= x.(!n - 1) then fail "collapsed grid cell";
      x.(!n) <- v;
      incr n
    in
    let upper = finite "initial domain" (4. *. float_max p.spot p.strike) in
    let cells = c.cfg.space_cells in
    for i = 0 to cells do
      append (upper *. (float i /. float cells))
    done;
    let insert v =
      let j = ref 0 in
      while !j < !n && x.(!j) < v do
        tick c;
        incr j
      done;
      if !j = !n then fail "missing interior anchor";
      if x.(!j) <> v then (
        if !n = capacity then raise (Stop (Resource_limit "grid anchors"));
        for k = !n downto !j + 1 do
          tick c;
          x.(k) <- x.(k - 1)
        done;
        x.(!j) <- v;
        incr n)
    in
    insert p.spot;
    insert p.strike;
    let split i =
      if !n = capacity then raise (Stop (Resource_limit "grid refinement"));
      let v = x.(i) +. (0.5 *. (x.(i + 1) -. x.(i))) in
      if v <= x.(i) || v >= x.(i + 1) then fail "unrepresentable grid midpoint";
      for k = !n downto i + 2 do
        tick c;
        x.(k) <- x.(k - 1)
      done;
      x.(i + 1) <- v;
      incr n
    in
    let balance () =
      let balanced = ref false in
      while not !balanced do
        balanced := true;
        let i = ref 1 in
        while !i < !n - 1 && !balanced do
          tick c;
          let a = x.(!i) -. x.(!i - 1) and b = x.(!i + 1) -. x.(!i) in
          if a > 2. *. b then (
            split (!i - 1);
            balanced := false)
          else if b > 2. *. a then (
            split !i;
            balanced := false);
          incr i
        done
      done
    in
    balance ();
    (* Domain expansion retains all original nodes; new cells are at most twice
       the preceding width. Subsequent bisections preserve all anchors. *)
    for _ = 1 to domain do
      let target = finite "expanded domain" (2. *. x.(!n - 1)) in
      while x.(!n - 1) < target do
        let last = x.(!n - 1) in
        let width = x.(!n - 1) -. x.(!n - 2) in
        append (float_min target (last +. (2. *. width)))
      done;
      balance ()
    done;
    for _ = 1 to level do
      let old = !n in
      for i = old - 2 downto 0 do
        split i
      done
    done;
    c.largest <- max c.largest !n;
    Array.sub x 0 !n

  type boundary_key = int64 * int64 * int64 option * int * int64 option
  type boundary_slot = { values : float array; errors : float array option }

  type boundary_cache = {
    mutable remaining : int;
    mutable boundary_bytes : int;
    mutable entries : (boundary_key * boundary_slot) list;
    keep_errors : bool;
  }

  (* Ordinary prices keep the original successful-scalar cache. A Greek request
     can retain it across volatility shifts, whose boundary inputs are fixed.
     Each reusable value retains its own arithmetic indicator: another solve's
     context must recheck its local allowance and rebuild its own maximum.
     Slab keys retain original words, not rounded intermediate time values.
     The 256-byte entry charge covers keys, option/record/array headers. *)
  let boundary_values ?top ~max_steps cache earlier later next_exercise
      time_steps =
    if
      (cache.remaining = 0 && cache.entries = [])
      || time_steps > max_steps
      || time_steps > Sys.max_floatarray_length
    then None
    else
      let key =
        ( Int64.bits_of_float earlier,
          Int64.bits_of_float later,
          Option.map Int64.bits_of_float next_exercise,
          time_steps,
          Option.map Int64.bits_of_float top )
      in
      match List.assoc_opt key cache.entries with
      | Some values -> Some values
      | None ->
          let per_step = if cache.keep_errors then 16 else 8 in
          if
            cache.remaining < 256
            || time_steps > (cache.remaining - 256) / per_step
          then None
          else
            let charge = 256 + (per_step * time_steps) in
            let values =
              {
                values = Array.make time_steps nan;
                errors =
                  (if cache.keep_errors then Some (Array.make time_steps nan)
                   else None);
              }
            in
            cache.remaining <- cache.remaining - charge;
            cache.boundary_bytes <- cache.boundary_bytes + charge;
            cache.entries <- (key, values) :: cache.entries;
            Some values

  let cached_boundary c slot i =
    match slot with
    | None -> nan
    | Some slot -> (
        let value = slot.values.(i) in
        if Float.is_nan value then value
        else
          match slot.errors with
          | None -> value
          | Some errors -> accept_boundary c value errors.(i))

  let store_boundary c slot i x =
    let v, e = enclosed x in
    let value = accept_boundary c v e in
    (match slot with
    | None -> ()
    | Some slot ->
        slot.values.(i) <- value;
        Option.iter (fun errors -> errors.(i) <- e) slot.errors);
    value

  (* The price request owns preparation for one stock-grid key. Payoff and
     spatial bands depend on that grid and the complete coefficient tuple;
     time steps, boundary choice and cash interpolation do not alter them. *)
  let solver_pair ?curves ?dates ?cash ?bermudan ~prepared ~stencils
      ~boundary_cache c p side x time_steps capture =
   fun upper_boundary ->
    check c;
    let n = Array.length x in
    let key p =
      ( Int64.bits_of_float p.rate,
        Int64.bits_of_float p.dividend_yield,
        Int64.bits_of_float (Vol.to_float p.volatility) )
    in
    let arr () = Array.make n 0. in
    let left, right, g, reused, switched =
      match !prepared with
      | None -> (arr (), arr (), arr (), false, 0)
      | Some (previous_key, left, right, g, switched) ->
          if
            Array.length left <> n
            || Array.length right <> n
            || Array.length g <> n
          then fail "prepared spatial grid mismatch";
          (left, right, g, previous_key = key p, switched)
    in
    let v = arr () in
    let lo = arr () and diag = arr () and hi = arr () and rhs = arr () in
    let d = arr () and z = arr () and candidate = arr () in
    let mask = Array.make n false and oldmask = Array.make n false in
    let history = Array.make c.cfg.limits.policy_iterations 0 in
    for i = 0 to n - 1 do
      tick c;
      if not reused then
        g.(i) <- boundary c (payoff_e side (exact x.(i)) (exact p.strike));
      v.(i) <- g.(i)
    done;
    let prepare p reused switched =
      let reused, switched =
        if reused || curves = None then (reused, switched)
        else
          match List.assoc_opt (key p) (snd !stencils) with
          | None -> (false, 0)
          | Some (saved_left, saved_right, switched) ->
              if Array.length saved_left <> n || Array.length saved_right <> n
              then fail "cached spatial grid mismatch";
              Array.blit saved_left 0 left 0 n;
              Array.blit saved_right 0 right 0 n;
              (true, switched)
      in
      let sigma = Vol.to_float p.volatility in
      if reused then (
        (* A logical stencil-row visit remains a visit when loading a prepared
         coefficient. Retain limits/cancellation and switched-row diagnostics. *)
        for _ = 1 to n - 2 do
          tick c
        done;
        c.switched <- c.switched + switched;
        prepared := Some (key p, left, right, g, switched))
      else
        let switched_before = c.switched in
        let drift = E.sub (exact p.rate) (exact p.dividend_yield) in
        let coefficient label value =
          let v, _ = enclosed value in
          if v < 0. || (v = 0. && E.sign value <> E.Zero) then fail label;
          v
        in
        for i = 1 to n - 2 do
          tick c;
          let hm = E.sub (exact x.(i)) (exact x.(i - 1))
          and hp = E.sub (exact x.(i + 1)) (exact x.(i)) in
          let sx = E.mul (exact sigma) (exact x.(i)) in
          let a2 = E.mul sx sx and b = E.mul drift (exact x.(i)) in
          let sum = E.add hm hp in
          let numerator_m = E.sub a2 (E.mul b hp)
          and numerator_p = E.add a2 (E.mul b hm) in
          let positive = function
            | E.Positive | E.Zero -> true
            | E.Negative -> false
            | E.Indeterminate -> fail "unresolved central stencil sign"
          in
          let central_m = positive (E.sign numerator_m)
          and central_p = positive (E.sign numerator_p) in
          let lm, lp =
            if central_m && central_p then
              ( E.div numerator_m (E.mul hm sum),
                E.div numerator_p (E.mul hp sum) )
            else (
              c.switched <- c.switched + 1;
              let diffusion_m = E.div a2 (E.mul hm sum)
              and diffusion_p = E.div a2 (E.mul hp sum) in
              match E.sign b with
              | E.Positive -> (diffusion_m, E.add diffusion_p (E.div b hp))
              | E.Negative ->
                  (E.add diffusion_m (E.div (E.neg b) hm), diffusion_p)
              | E.Zero -> (diffusion_m, diffusion_p)
              | E.Indeterminate -> fail "unresolved upwind direction")
          in
          left.(i) <- coefficient "left spatial coefficient resolution" lm;
          right.(i) <- coefficient "right spatial coefficient resolution" lp
        done;
        let switched = c.switched - switched_before in
        prepared := Some (key p, left, right, g, switched);
        (* The arrays above remain mutable working bands. Retain separate,
           immutable snapshots, charged to the same surplus as boundary values.
           A 256-byte entry allowance covers keys, boxes and headers. *)
        let remaining = boundary_cache.remaining in
        if curves <> None && remaining >= 256 && n <= (remaining - 256) / 16
        then (
          let charge = 256 + (16 * n) in
          let used, entries = !stencils in
          stencils :=
            ( used + charge,
              (key p, (Array.copy left, Array.copy right, switched)) :: entries
            );
          boundary_cache.remaining <- remaining - charge)
    in
    prepare p reused switched;
    let current_key = ref (key p) in
    let residual_state =
      American_residual.create ~lo ~diag ~hi ~rhs ~values:v ~payoff:g
    in
    let residual obstacle =
      American_residual.reset residual_state ~obstacle;
      let i = ref 1 in
      while !i <= n - 2 do
        (* Preserve the exact pre-row budget/callback order. After this tick,
           following rows stop before the next callback or budget edge. *)
        tick c;
        let following =
          min
            (n - 2 - !i)
            (min
               (255 - (c.visits land 255))
               (c.cfg.limits.max_row_visits - c.visits))
        in
        let status =
          American_residual.run residual_state ~first:!i ~last:(!i + following)
        in
        let visited = American_residual.visited residual_state in
        c.visits <- c.visits + visited - 1;
        if status = 1 then fail "original residual";
        if status = 2 then fail "residual roundoff screen";
        i := !i + visited
      done;
      let indicator = American_residual.indicator residual_state in
      c.roundoff <- float_max c.roundoff indicator;
      if indicator > c.local /. 4. then fail "residual roundoff resolution";
      ( American_residual.worst residual_state,
        American_residual.worst_row residual_state )
    in
    let slab_constant ?next_exercise p earlier later obstacle =
      if earlier < later then (
        if key p <> !current_key then (
          prepare p false 0;
          current_key := key p);
        let piecewise_bounds =
          Option.map
            (fun cs ->
              let tick () = tick c in
              let optimum =
                if side = Side.Call then exact 0.
                else discount_optimum tick cs.rates dates p later
              in
              let future_cap =
                curve_integral tick
                  (if side = Side.Call then cs.yields else cs.rates)
                  later p.time_to_expiry
                  (fun v -> exact (float_max (-.v) 0.))
              in
              (optimum, future_cap))
            curves
        in
        let width = E.sub (exact later) (exact earlier) in
        let h_e = E.div_float width (float time_steps) in
        let h = finite "time increment" (centre h_e) in
        if h <= 0. then fail "collapsed time step";
        if h *. float_max (-.p.rate) 0. > 0.5 then
          fail "negative-rate matrix margin";
        let zero_values =
          boundary_values ~max_steps:c.cfg.limits.max_steps boundary_cache
            earlier later next_exercise time_steps
        in
        let top_values =
          if upper_boundary && curves <> None then
            boundary_values
              ~top:(if side = Side.Call then x.(n - 1) else p.strike)
              ~max_steps:c.cfg.limits.max_steps boundary_cache earlier later
              next_exercise time_steps
          else None
        in
        let previous = ref later in
        for j = 1 to time_steps do
          step c;
          let t_e =
            if j = time_steps then exact earlier
            else E.sub (exact later) (E.mul_float h_e (float j))
          in
          let t = centre t_e in
          if (not (t < !previous)) || t < earlier then
            fail "collapsed time coordinates";
          previous := t;
          let remaining = E.sub (exact p.time_to_expiry) t_e in
          let wait =
            match next_exercise with
            | Some date -> E.sub (exact date) t_e
            | None ->
                if t >= p.opens_at then exact 0.
                else E.sub (exact p.opens_at) t_e
          in
          let zero =
            if side = Side.Call then 0.
            else
              let cached = cached_boundary c zero_values (j - 1) in
              if not (Float.is_nan cached) then cached
              else
                let value =
                  match piecewise_bounds with
                  | Some (optimum, _) ->
                      let exponent =
                        E.sub optimum
                          (E.mul (exact p.rate) (E.sub (exact later) t_e))
                      in
                      let exponent =
                        if obstacle then maximum_enclosure (exact 0.) exponent
                        else exponent
                      in
                      store_boundary c zero_values (j - 1)
                        (E.mul (exact p.strike) (E.exp exponent))
                  | None ->
                      store_boundary c zero_values (j - 1)
                        (E.mul (exact p.strike)
                           (exp_product (-.p.rate)
                              (if p.rate < 0. then remaining else wait)))
                in
                value
          in
          let top =
            if upper_boundary then
              let cached = cached_boundary c top_values (j - 1) in
              if not (Float.is_nan cached) then cached
              else
                let factor =
                  match piecewise_bounds with
                  | Some (_, future_cap) ->
                      E.exp
                        (E.add future_cap
                           (E.mul
                              (exact
                                 (float_max
                                    (if side = Side.Call then -.p.dividend_yield
                                     else -.p.rate)
                                    0.))
                              (E.sub (exact later) t_e)))
                  | None ->
                      exp_product
                        (float_max
                           (if side = Side.Call then -.p.dividend_yield
                            else -.p.rate)
                           0.)
                        remaining
                in
                let value =
                  store_boundary c top_values (j - 1)
                    (E.mul
                       (exact
                          (if side = Side.Call then x.(n - 1) else p.strike))
                       factor)
                in
                value
            else if obstacle then g.(n - 1)
            else 0.
          in
          v.(0) <- zero;
          v.(n - 1) <- top;
          (* h, coefficients and original bands are fixed within this slab;
             policy elimination writes only d/z/candidate. Check the first
             assembly in its original row/step order, then retain the bands.
             Every logical row visit and RHS update still occurs each step. *)
          let assemble = j = 1 in
          for i = 1 to n - 2 do
            tick c;
            if assemble then (
              lo.(i) <- -.h *. left.(i);
              hi.(i) <- -.h *. right.(i);
              diag.(i) <- 1. +. (h *. (left.(i) +. right.(i) +. p.rate));
              rhs.(i) <- v.(i);
              let margin =
                finite "assembled matrix margin" (diag.(i) +. lo.(i) +. hi.(i))
              in
              if margin < 0.25 || diag.(i) <= 0. then
                fail "lost binary64 matrix dominance")
            else rhs.(i) <- v.(i)
          done;
          let accepted = ref false and iteration = ref 0 in
          while not !accepted do
            (if !iteration >= c.cfg.limits.policy_iterations then
               let r, row = residual obstacle in
               raise
                 (Stop (Nonconvergence { step = c.steps; row; residual = r })));
            policy c;
            incr iteration;
            let changed = ref false and fingerprint = ref 17 in
            for i = 1 to n - 2 do
              tick c;
              oldmask.(i) <- mask.(i);
              let pvalue =
                Float.fma lo.(i)
                  v.(i - 1)
                  (Float.fma diag.(i) v.(i)
                     (Float.fma hi.(i) v.(i + 1) (-.rhs.(i))))
              in
              ignore (finite "policy decision" pvalue);
              mask.(i) <- obstacle && pvalue > v.(i) -. g.(i);
              fingerprint :=
                !fingerprint * 65599 lxor if mask.(i) then i else -i;
              if mask.(i) <> oldmask.(i) then changed := true;
              d.(i) <- (if mask.(i) then 1. else diag.(i));
              z.(i) <- (if mask.(i) then g.(i) else rhs.(i))
            done;
            (* Eliminate known boundaries once, retaining full original bands
               for the independent residual. Identity rows have zero bands. *)
            if not mask.(1) then z.(1) <- z.(1) -. (lo.(1) *. zero);
            if not mask.(n - 2) then
              z.(n - 2) <- z.(n - 2) -. (hi.(n - 2) *. top);
            for i = 2 to n - 2 do
              tick c;
              if d.(i - 1) <= 0. then fail "nonpositive elimination pivot";
              let mult = if mask.(i) then 0. else lo.(i) /. d.(i - 1) in
              let prev_hi = if mask.(i - 1) then 0. else hi.(i - 1) in
              d.(i) <- finite "elimination pivot" (d.(i) -. (mult *. prev_hi));
              z.(i) <-
                finite "elimination right hand side"
                  (z.(i) -. (mult *. z.(i - 1)))
            done;
            for i = n - 2 downto 1 do
              tick c;
              if d.(i) <= 0. then fail "nonpositive back substitution pivot";
              let next =
                if i = n - 2 || mask.(i) then 0.
                else hi.(i) *. candidate.(i + 1)
              in
              candidate.(i) <-
                finite "back substitution" ((z.(i) -. next) /. d.(i))
            done;
            for i = 1 to n - 2 do
              tick c;
              v.(i) <- candidate.(i)
            done;
            let r, row = residual obstacle in
            (if r <= c.local then (
               accepted := true;
               c.residual <- float_max c.residual r)
             else
               let repeated = ref ((not !changed) && !iteration > 1) in
               for k = 0 to !iteration - 2 do
                 tick c;
                 if history.(k) = !fingerprint then repeated := true
               done;
               if !repeated then
                 raise
                   (Stop (Nonconvergence { step = c.steps; row; residual = r })));
            history.(!iteration - 1) <- !fingerprint
          done
        done)
    in
    let slab ?next_exercise earlier later obstacle =
      match curves with
      | None -> slab_constant ?next_exercise p earlier later obstacle
      | Some cs ->
          let run a b =
            if a < b then
              let volatility =
                match Vol.lognormal (curve_level cs.vols a) with
                | Ok v -> v
                | Error _ -> fail "admitted volatility invariant"
              in
              slab_constant ?next_exercise
                {
                  p with
                  rate = curve_level cs.rates a;
                  dividend_yield = curve_level cs.yields a;
                  volatility;
                }
                a b obstacle
          in
          let previous = ref later in
          List.iter
            (fun t ->
              tick c;
              if t > earlier && t < !previous then (
                run t !previous;
                previous := t))
            (List.rev cs.knots);
          run earlier !previous
    in
    let project () =
      for i = 0 to n - 1 do
        tick c;
        v.(i) <- float_max v.(i) g.(i)
      done
    in
    let jump =
      match cash with
      | None -> fun _ -> fail "missing cash mapping"
      | Some (_, _, mapping_grid) ->
          let sampled = Array.make (Array.length mapping_grid) 0. in
          let interpolate nodes values point =
            tick c;
            let last = Array.length nodes - 1 in
            let vpoint = centre point in
            let low = ref 0 and high = ref last in
            while !high - !low > 1 do
              tick c;
              let mid = !low + ((!high - !low) / 2) in
              if nodes.(mid) <= vpoint then low := mid else high := mid
            done;
            if E.compare_float point nodes.(!low) = E.Zero then values.(!low)
            else if E.compare_float point nodes.(!high) = E.Zero then
              values.(!high)
            else
              let width = E.sub (exact nodes.(!high)) (exact nodes.(!low)) in
              let weight = E.div (E.sub point (exact nodes.(!low))) width in
              (match (E.compare_float weight 0., E.compare_float weight 1.) with
              | E.Positive, E.Negative -> ()
              | _ -> fail "cash interpolation weight unresolved");
              let value, error =
                enclosed
                  (E.add
                     (E.mul (E.sub (exact 1.) weight) (exact values.(!low)))
                     (E.mul weight (exact values.(!high))))
              in
              c.mapping_width <-
                float_max c.mapping_width (nodes.(!high) -. nodes.(!low));
              c.mapping_error <- float_max c.mapping_error error;
              if error > c.local then
                fail "cash interpolation arithmetic resolution";
              nonnegative "cash interpolated value" value
          in
          fun amount ->
            for i = 0 to Array.length mapping_grid - 1 do
              let target =
                positive_part (E.sub (exact mapping_grid.(i)) amount)
              in
              sampled.(i) <- interpolate x v target
            done;
            for i = 0 to n - 1 do
              candidate.(i) <- interpolate mapping_grid sampled (exact x.(i))
            done;
            Array.blit candidate 0 v 0 n;
            c.event_applications <- c.event_applications + 1
    in
    (match (bermudan, cash) with
    | Some timeline, _ ->
        let later = ref p.time_to_expiry and next = ref p.time_to_expiry in
        List.iter
          (fun (time, amount, regular, before, after) ->
            check c;
            slab ~next_exercise:!next time !later false;
            if after then project ();
            (match (amount, cash) with
            | Some a, Some (spec, _, _) when active_jump p spec time -> jump a
            | _ -> ());
            if before || regular then project ();
            if regular || before || after then next := time;
            later := time)
          (List.rev timeline);
        slab ~next_exercise:!next 0. !later false
    | None, None ->
        slab p.opens_at p.time_to_expiry true;
        slab 0. p.opens_at false
    | None, Some (spec, events, _) ->
        let exercise phase time =
          if eligible p spec time phase then project ()
        in
        let later = ref p.time_to_expiry in
        let advance earlier =
          if earlier < p.opens_at && p.opens_at < !later then (
            slab p.opens_at !later true;
            slab earlier p.opens_at false)
          else slab earlier !later (earlier >= p.opens_at);
          later := earlier
        in
        List.iter
          (fun (time, amount) ->
            check c;
            advance time;
            if active_jump p spec time then (
              exercise After_cash time;
              jump amount;
              exercise Before_cash time))
          (List.rev events);
        advance 0.);

    let spot_index = ref 0 in
    for i = 0 to n - 1 do
      tick c;
      if x.(i) = p.spot then spot_index := i
    done;
    let value = nonnegative "spot price" v.(!spot_index) in
    (value, if capture then Some v else None)

  let price_with_curves ?curves ?observe ?boundary_reuse
      ?(cancel = fun () -> false) ?(exercise_regions = false) ?(premium = false)
      cfg admitted side =
    let p = inputs admitted in
    let cash =
      match admitted with
      | Admitted _ | Bermudan (_, None, _) -> None
      | With_cash (_, spec) | Bermudan (_, Some spec, _) ->
          if Array.length spec.dividends = 0 then None else Some spec
    in
    try
      if cancel () then raise (Stop Cancelled);
      if cfg.limits.max_workspace_bytes < 65536 then
        raise (Stop (Resource_limit "analytic workspace bytes"));
      let cash_visits = ref 0 in
      let active_context = ref None in
      let model_tick () =
        match !active_context with
        | Some c -> tick c
        | None ->
            if cancel () then raise (Stop Cancelled);
            incr cash_visits;
            if !cash_visits > cfg.limits.max_row_visits then
              raise (Stop (Resource_limit "coefficient visits"))
      in
      let curve_count =
        match curves with
        | None -> 0
        | Some cs ->
            List.fold_left
              (fun n curve ->
                let count = Array.length curve.changes + 1 in
                let budget =
                  max 0 (cfg.limits.max_workspace_bytes - 65536) / 1024
                in
                if count > budget - n then
                  raise (Stop (Resource_limit "coefficient metadata"));
                n + count)
              0
              [ cs.rates; cs.yields; cs.vols ]
      in
      let model_european () =
        match curves with
        | None -> european p side
        | Some cs -> piecewise_european model_tick cs p side
      in
      let events =
        match cash with
        | None -> []
        | Some spec -> prepare_cash cfg cancel cash_visits spec
      in
      let dates =
        match admitted with Bermudan (_, _, dates) -> Some dates | _ -> None
      in
      let cash_count =
        match cash with None -> 0 | Some c -> Array.length c.dividends
      in
      if
        curves <> None
        && curve_count + cash_count
           + Option.fold ~none:0 ~some:Array.length dates
           > max 0 (cfg.limits.max_workspace_bytes - 65536) / 1024
      then raise (Stop (Resource_limit "coefficient and event metadata"));
      let bermudan =
        Option.map
          (fun dates ->
            prepare_bermudan cfg cancel cash_visits dates events cash_count)
          dates
      in
      let immediate =
        match (dates, cash) with
        | Some ds, _ -> (
            ds.(0).time = 0.
            && ds.(0).side
               = match cash with None -> Regular | Some c -> c.valuation_side)
        | None, None -> p.opens_at = 0.
        | None, Some spec -> eligible p spec 0. spec.valuation_side
      in
      let allowance = cfg.tolerance /. 64. in
      let make_result method_name value arithmetic refinement work residual
          roundoff boundary_error regions mapping =
        ignore (nonnegative "accepted price" value);
        let premium_result =
          if not premium then Not_requested
          else if cash <> None then
            Unavailable "matching cash-European comparison not implemented"
          else
            try
              if cancel () then raise (Stop Cancelled);
              let ev, ee = model_european () in
              if ee > allowance then
                Unavailable "European comparison arithmetic resolution"
              else
                let difference = E.sub (exact value) (exact ev) in
                let pv, pe = enclosed difference in
                Available
                  {
                    value = pv;
                    european_value = ev;
                    european_absolute_error = ee;
                    subtraction_indicator = pe;
                  }
            with
            | E.Unresolved message -> Unavailable message
            | Stop Cancelled -> raise (Stop Cancelled)
            | Stop _ -> Unavailable "European comparison arithmetic unresolved"
        in
        if cancel () then raise (Stop Cancelled);
        {
          value;
          assurance = Estimated_only;
          method_name;
          requested_tolerance = cfg.tolerance;
          refinement;
          mapping;
          maximum_residual = residual;
          maximum_roundoff_indicator = float_max arithmetic roundoff;
          boundary_arithmetic_indicator = boundary_error;
          work =
            (match curves with
            | None -> work
            | Some _ ->
                {
                  work with
                  row_visits =
                    (match !active_context with
                    | None -> !cash_visits
                    | Some c -> c.visits);
                });
          exercise_regions = regions;
          early_exercise_premium = premium_result;
        }
      in
      let analytical =
        match curves with
        | Some cs -> piecewise_analytic model_tick cs p cash events dates side
        | None -> (
            match (bermudan, cash) with
            | Some timeline, _ ->
                bermudan_analytic cfg cancel cash_visits p cash timeline side
            | None, None -> analytic p side
            | None, Some spec ->
                cash_analytic cfg cancel cash_visits p spec events side)
      in
      match analytical with
      | Some (method_name, (value, error)) ->
          if error > allowance then fail "analytic arithmetic resolution";
          let work =
            {
              steps = 0;
              policy_solves = 0;
              row_visits = !cash_visits;
              largest_grid = 0;
              final_nodes = 0;
              final_upper_stock = 0.;
              finest_steps_per_slab = 0;
              domain_expansions = 0;
              switched_rows = 0;
            }
          in
          Ok
            (make_result method_name value error None work 0. 0. error
               (if exercise_regions then
                  Unavailable "no sampled grid on analytic route"
                else Not_requested)
               None)
      | None ->
          let gamma =
            match curves with
            | Some cs ->
                let gv, ge =
                  enclosed
                    (E.exp
                       (E.mul_float
                          (curve_integral model_tick cs.rates 0.
                             p.time_to_expiry (fun r ->
                               exact (float_max (-.r) 0.)))
                          2.))
                in
                finite "piecewise stability"
                  (Float.next_after (gv +. ge) infinity)
            | None ->
                if p.rate >= 0. then 1.
                else
                  let gv, ge =
                    enclosed
                      (E.exp
                         (E.mul_float
                            (E.mul (exact (-.p.rate)) (exact p.time_to_expiry))
                            2.))
                  in
                  finite "negative-rate stability"
                    (Float.next_after (gv +. ge) infinity)
          in
          let local =
            cfg.tolerance /. (64. *. float cfg.limits.max_steps *. gamma)
          in
          if (not (Float.is_finite local)) || local <= 0. then
            fail "unresolvable local allowance";
          let c =
            {
              cfg;
              cancel;
              steps = 0;
              policies = 0;
              visits = !cash_visits;
              largest = 0;
              switched = 0;
              residual = 0.;
              roundoff = 0.;
              boundary_error = 0.;
              event_applications = 0;
              mapping_width = 0.;
              mapping_error = 0.;
              local;
            }
          in
          active_context := Some c;
          check_workspace c;
          (if curve_count > 0 then
             let metadata =
               cash_count + Option.fold ~none:0 ~some:Array.length dates
             in
             let reserved =
               (512 * cfg.limits.max_nodes)
               + (32 * cfg.limits.policy_iterations)
               + 65536
               + if cash = None then 0 else 48 * cfg.limits.max_nodes
             in
             if
               curve_count + metadata
               > max 0 (cfg.limits.max_workspace_bytes - reserved) / 1024
             then
               raise
                 (Stop (Resource_limit "coefficient solver workspace bytes")));
          (match dates with
          | None -> ()
          | Some ds ->
              let reserved =
                (512 * cfg.limits.max_nodes)
                + (32 * cfg.limits.policy_iterations)
                + 65536
                + if cash = None then 0 else 48 * cfg.limits.max_nodes
              in
              if
                Array.length ds + cash_count
                > max 0 (cfg.limits.max_workspace_bytes - reserved) / 1024
              then raise (Stop (Resource_limit "Bermudan workspace bytes")));
          (match cash with
          | None -> ()
          | Some spec ->
              let reserved =
                (512 * cfg.limits.max_nodes)
                + (32 * cfg.limits.policy_iterations)
                + 65536
              in
              let remaining = cfg.limits.max_workspace_bytes - reserved in
              if
                remaining < 0
                || cfg.limits.max_nodes > remaining / 48
                || Array.length spec.dividends
                   > (remaining - (48 * cfg.limits.max_nodes)) / 1024
              then raise (Stop (Resource_limit "cash workspace bytes")));

          (* Existing checks above make each reservation fit before these
             products are formed. Reuse is optional: insufficient surplus keeps
             the original evaluator, including its original resource outcomes. *)
          let metadata =
            curve_count + cash_count
            + Option.fold ~none:0 ~some:Array.length dates
          in
          let reserved =
            (512 * cfg.limits.max_nodes)
            + (32 * cfg.limits.policy_iterations)
            + 65536 + (1024 * metadata)
            + if cash = None then 0 else 48 * cfg.limits.max_nodes
          in
          let cache_bytes =
            if
              curves = None
              && (side = Side.Call
                 || (dates = None && p.rate >= 0. && p.opens_at = 0.))
            then 0
            else
              max 0
                (cfg.limits.max_workspace_bytes - reserved
                - if curves = None then 128 else 256)
          in
          let fresh () =
            {
              remaining = cache_bytes;
              boundary_bytes = 0;
              entries = [];
              keep_errors = Option.is_some boundary_reuse;
            }
          in
          let boundary_cache =
            match boundary_reuse with
            | None -> fresh ()
            | Some reuse ->
                let cache =
                  match !reuse with
                  | Some cache when cache.boundary_bytes <= cache_bytes ->
                      (* The previous solve's stencil snapshots are no longer
                         retained. Only the boundary entries cross this call. *)
                      cache.remaining <- cache_bytes - cache.boundary_bytes;
                      cache
                  | _ -> fresh ()
                in
                reuse := Some cache;
                cache
          in
          let fine_time = 4 * cfg.time_steps in
          (* Single-entry, request-owned cache. grid is deterministic in the
             fixed inputs/configuration plus (level, domain). Drop the previous
             preparation before constructing a different grid. *)
          let spatial = ref None in
          let stencils = ref (0, []) in
          let run ?(mapping_level = 2) level domain time capture =
            let prepared =
              match !spatial with
              | Some (l, d, prepared) when l = level && d = domain -> prepared
              | _ ->
                  let used, _ = !stencils in
                  stencils := (0, []);
                  boundary_cache.remaining <- boundary_cache.remaining + used;
                  let prepared = ref None in
                  spatial := Some (level, domain, prepared);
                  prepared
            in
            let x = grid c p level domain in
            let cash =
              Option.map
                (fun spec ->
                  ( spec,
                    events,
                    if level = mapping_level then x
                    else grid c p mapping_level domain ))
                cash
            in
            let solve =
              solver_pair ?curves ?dates ?cash ?bermudan ~prepared ~stencils
                ~boundary_cache c p side x time
                (capture || Option.is_some observe)
            in
            let low, vl = solve false in
            let high, vh = solve true in
            if high < low then fail "reversed boundary pair";
            (match (observe, vl, vh) with
            | Some f, Some vl, Some vh -> f c x vl vh
            | _ -> ());
            let midpoint = low +. (0.5 *. (high -. low)) in
            (midpoint, 0.5 *. (high -. low), x, vl, vh)
          in
          let value_of (v, _, _, _, _) = v in
          let d0 =
            value_of (run 2 (cfg.domain_expansions - 2) fine_time false)
          in
          let d1 =
            value_of (run 2 (cfg.domain_expansions - 1) fine_time false)
          in
          let s0 = value_of (run 0 cfg.domain_expansions fine_time false) in
          let s1 = value_of (run 1 cfg.domain_expansions fine_time false) in
          let t0 =
            value_of (run 2 cfg.domain_expansions cfg.time_steps false)
          in
          let t1 =
            value_of (run 2 cfg.domain_expansions (2 * cfg.time_steps) false)
          in
          let mapping_values =
            match cash with
            | None -> None
            | Some _ ->
                Some
                  ( value_of
                      (run ~mapping_level:0 2 cfg.domain_expansions fine_time
                         false),
                    value_of
                      (run ~mapping_level:1 2 cfg.domain_expansions fine_time
                         false) )
          in
          let value, spread, x, vl, vh =
            run 2 cfg.domain_expansions fine_time exercise_regions
          in
          let sc = (abs_float (s1 -. s0), abs_float (value -. s1))
          and tc = (abs_float (t1 -. t0), abs_float (value -. t1))
          and dc = (abs_float (d1 -. d0), abs_float (value -. d1)) in
          let ec =
            Option.map
              (fun (a, b) -> (abs_float (b -. a), abs_float (value -. b)))
              mapping_values
          in
          let sum =
            snd sc +. snd tc +. snd dc +. spread
            +. match ec with None -> 0. | Some (_, b) -> b
          in
          let refinement =
            {
              space_changes = sc;
              time_changes = tc;
              domain_changes = dc;
              event_changes = ec;
              boundary_half_spread = spread;
              observed_sum = sum;
            }
          in
          let small (a, b) =
            Float.is_finite a && Float.is_finite b
            && float_max a b <= cfg.tolerance /. 8.
          in
          if
            (not
               (small sc && small tc && small dc
               && Option.fold ~none:true ~some:small ec))
            || spread > cfg.tolerance /. 8.
            || sum > cfg.tolerance /. 2.
          then raise (Stop (Accuracy_not_demonstrated refinement));
          (* Independent global financial inequalities, allowing only the recorded
             arithmetic uncertainty, never clipping a value to fit. *)
          let cap =
            match curves with
            | Some cs ->
                boundary c
                  (E.mul
                     (exact (if side = Side.Call then p.spot else p.strike))
                     (E.exp
                        (curve_integral
                           (fun () -> tick c)
                           (if side = Side.Call then cs.yields else cs.rates)
                           0. p.time_to_expiry
                           (fun v -> exact (float_max (-.v) 0.)))))
            | None ->
                boundary c
                  (E.mul
                     (exact (if side = Side.Call then p.spot else p.strike))
                     (exp_product
                        (float_max
                           (if side = Side.Call then -.p.dividend_yield
                            else -.p.rate)
                           0.)
                        (exact p.time_to_expiry)))
          in
          if value > cap +. c.boundary_error then fail "global price cap";
          (if immediate then
             let intrinsic =
               boundary c (payoff_e side (exact p.spot) (exact p.strike))
             in
             if value < intrinsic -. c.boundary_error then
               fail "immediate exercise lower bound");
          (if cash = None then
             let ev, ee = model_european () in
             if value +. sum +. c.boundary_error < ev -. ee then
               fail
                 "matching European lower bound beyond refinement diagnostics");
          let regions =
            try
              if not exercise_regions then Not_requested
              else if not immediate then
                Unavailable
                  (if dates = None then "exercise window has not opened"
                   else "valuation instant is not an exercise right")
              else
                match (vl, vh) with
                | Some a, Some b ->
                    let result = ref [] in
                    let classify i =
                      let g =
                        boundary c
                          (payoff_e side (exact x.(i)) (exact p.strike))
                      in
                      if
                        g > 0.
                        && abs_float (a.(i) -. g) <= local
                        && abs_float (b.(i) -. g) <= local
                      then Estimated_exercise
                      else if a.(i) > g +. local && b.(i) > g +. local then
                        Estimated_continuation
                      else Unresolved
                    in
                    let previous = ref (classify 0) in
                    for i = 0 to Array.length x - 2 do
                      tick c;
                      let next = classify (i + 1) in
                      let kind =
                        if !previous = next then next else Unresolved
                      in
                      (match !result with
                      | h :: tail when h.kind = kind ->
                          result := { h with upper_stock = x.(i + 1) } :: tail
                      | _ ->
                          result :=
                            {
                              lower_stock = x.(i);
                              upper_stock = x.(i + 1);
                              kind;
                            }
                            :: !result);
                      previous := next
                    done;
                    Available (List.rev !result)
                | _ -> Unavailable "no captured exercise grid"
            with
            | Stop (Resource_limit reason) ->
                Unavailable ("region resource limit: " ^ reason)
            | E.Unresolved reason -> Unavailable reason
          in
          let work =
            {
              steps = c.steps;
              policy_solves = c.policies;
              row_visits = c.visits;
              largest_grid = c.largest;
              final_nodes = Array.length x;
              final_upper_stock = x.(Array.length x - 1);
              finest_steps_per_slab = fine_time;
              domain_expansions = cfg.domain_expansions;
              switched_rows = c.switched;
            }
          in
          Ok
            (make_result
               (if dates = None then "backward-Euler-policy-v1"
                else "backward-Euler-Bermudan-v1")
               value 0. (Some refinement) work c.residual c.roundoff
               c.boundary_error regions
               (Option.map
                  (fun _ ->
                    {
                      event_applications = c.event_applications;
                      maximum_cell_width = c.mapping_width;
                      arithmetic_indicator = c.mapping_error;
                    })
                  cash))
    with
    | Stop failure -> Error failure
    | E.Unresolved message -> Error (Arithmetic_unresolved message)

  let price ?cancel ?exercise_regions ?premium cfg admitted side =
    price_with_curves ?cancel ?exercise_regions ?premium cfg admitted side

  type greek = Delta | Gamma | Vega | Rho | Theta

  type greek_request = {
    quantity : greek;
    tolerance : float;
    bump : float option;
  }

  type greek_configuration = greek_request list

  let request_greek ?bump ~tolerance quantity =
    if (not (Float.is_finite tolerance)) || tolerance <= 0. then
      Error "positive finite Greek tolerance required"
    else
      match (quantity, bump) with
      | (Vega | Rho), Some h when Float.is_finite h && h > 0. && h /. 4. > 0. ->
          Ok { quantity; tolerance; bump }
      | (Delta | Gamma | Theta), None -> Ok { quantity; tolerance; bump }
      | (Vega | Rho), _ ->
          Error "vega/rho require a positive finite resolvable bump"
      | _ -> Error "only vega/rho take a bump"

  let configure_greeks requests =
    let rec valid seen = function
      | [] -> true
      | r :: tail ->
          (not (List.mem r.quantity seen)) && valid (r.quantity :: seen) tail
    in
    if requests = [] || not (valid [] requests) then
      Error "request one to five distinct Greeks"
    else Ok requests

  type greek_diagnostics = {
    derivative_refinement : refinement option;
    bump_changes : (float * float) option;
    stencil_change : float;
    arithmetic_indicator : float;
    amplified_price_indicator : float;
  }

  type estimated_greek = {
    value : float;
    assurance : assurance;
    requested_tolerance : float;
    method_name : string;
    diagnostics : greek_diagnostics;
  }

  type greek_outcome =
    | Greek_estimate of estimated_greek
    | Greek_unavailable of string
    | Greek_failure of failure
    | Greek_accuracy_not_demonstrated of greek_diagnostics

  type perturbation_price = {
    quantity : greek;
    shift : float;
    price : estimated_price;
  }

  type estimated_greeks = {
    price : estimated_price;
    greeks : (greek * greek_outcome) list;
    perturbation_prices : perturbation_price list;
  }

  type derivative_sample = {
    sample_value : float;
    sample_spread : float;
    sample_stencil : float;
    sample_arithmetic : float;
    sample_condition : float;
  }

  type greek_observation = {
    stock_delta : (derivative_sample, string) result;
    stock_gamma : (derivative_sample, string) result;
    calendar_theta : (derivative_sample, string) result;
    point_price : derivative_sample;
  }

  let greek_cash = function
    | Admitted _ | Bermudan (_, None, _) -> None
    | With_cash (_, c) | Bermudan (_, Some c, _) -> Some c

  let greek_immediate admitted =
    let p = inputs admitted in
    let phase =
      match greek_cash admitted with
      | None -> Regular
      | Some c -> c.valuation_side
    in
    match admitted with
    | Bermudan (_, _, ds) -> ds.(0).time = 0. && ds.(0).side = phase
    | _ -> (
        p.opens_at = 0.
        &&
        match greek_cash admitted with
        | None -> true
        | Some c -> rank phase >= rank c.opening_side)

  let theta_event admitted =
    let p = inputs admitted in
    p.time_to_expiry = 0.
    || (match admitted with
       | Bermudan (_, _, ds) -> ds.(0).time = 0.
       | _ -> false)
    ||
    match greek_cash admitted with
    | None -> false
    | Some c -> Array.length c.dividends > 0 && c.dividends.(0).time = 0.

  let observe_greeks admitted side c x low high =
    let p = inputs admitted in
    let i = ref 0 in
    while !i < Array.length x && x.(!i) <> p.spot do
      tick c;
      incr i
    done;
    if !i = Array.length x then fail "missing Greek spot anchor";
    let i = !i in
    let point_price =
      {
        sample_value = low.(i) +. (0.5 *. (high.(i) -. low.(i)));
        sample_spread = 0.5 *. (high.(i) -. low.(i));
        sample_stencil = 0.;
        sample_arithmetic = c.roundoff +. c.boundary_error;
        sample_condition = 1.;
      }
    in
    let unavailable reason =
      {
        stock_delta = Error reason;
        stock_gamma = Error reason;
        calendar_theta = Error reason;
        point_price;
      }
    in
    if
      match greek_cash admitted with
      | Some cash -> cash.valuation_side = Before_cash
      | None -> false
    then
      unavailable "spot Greeks before a valuation cash jump are not qualified"
    else if i < 2 || i + 2 >= Array.length x then
      unavailable "spot has no two-sided derivative stencil"
    else
      try
        let immediate = greek_immediate admitted in
        let classify j =
          tick c;
          if not immediate then Estimated_continuation
          else
            let g = centre (payoff_e side (exact x.(j)) (exact p.strike)) in
            if
              g > 0.
              && abs_float (low.(j) -. g) <= c.local
              && abs_float (high.(j) -. g) <= c.local
            then Estimated_exercise
            else if low.(j) > g +. c.local && high.(j) > g +. c.local then
              Estimated_continuation
            else Unresolved
        in
        let kind = classify i in
        let smooth = ref (kind <> Unresolved) in
        for j = i - 2 to i + 2 do
          if classify j <> kind then smooth := false
        done;
        if not !smooth then
          unavailable
            "exercise transition or unresolved derivative neighborhood"
        else
          let stencil values width =
            tick c;
            let a = E.sub (exact x.(i)) (exact x.(i - width))
            and b = E.sub (exact x.(i + width)) (exact x.(i)) in
            let l =
              E.div (E.sub (exact values.(i)) (exact values.(i - width))) a
            and r =
              E.div (E.sub (exact values.(i + width)) (exact values.(i))) b
            in
            let span = E.add a b in
            ( E.div (E.add (E.mul b l) (E.mul a r)) span,
              E.div (E.mul_float (E.sub r l) 2.) span )
          in
          let ld, lg = stencil low 1
          and hd, hg = stencil high 1
          and wd, wg = stencil low 2
          and zd, zg = stencil high 2 in
          let sample condition l h w z =
            let v, e = enclosed (E.mul_float (E.add l h) 0.5) in
            let lv, le = enclosed l
            and hv, he = enclosed h
            and wv, we = enclosed w
            and zv, ze = enclosed z in
            {
              sample_value = v;
              sample_spread = 0.5 *. abs_float (hv -. lv);
              sample_stencil =
                float_max (abs_float (lv -. wv)) (abs_float (hv -. zv));
              sample_arithmetic = e +. le +. he +. we +. ze;
              sample_condition = condition;
            }
          in
          let theta values d g =
            if kind = Estimated_exercise then exact 0.
            else
              E.div_float
                (E.sub
                   (E.sub
                      (E.mul_float (exact values.(i)) p.rate)
                      (E.mul
                         (E.sub (exact p.rate) (exact p.dividend_yield))
                         (E.mul (exact p.spot) d)))
                   (E.mul_float
                      (E.mul
                         (E.mul
                            (exact (Vol.to_float p.volatility))
                            (exact (Vol.to_float p.volatility)))
                         (E.mul (E.mul (exact p.spot) (exact p.spot)) g))
                      0.5))
                365.
          in
          let a = x.(i) -. x.(i - 1) and b = x.(i + 1) -. x.(i) in
          let delta_condition = 2. /. float_min a b
          and gamma_condition = 4. /. (a *. b) in
          let theta_condition =
            if kind = Estimated_exercise then 0.
            else
              (abs_float p.rate
              +. abs_float (p.rate -. p.dividend_yield)
                 *. p.spot *. delta_condition
              +. 0.5 *. Vol.to_float p.volatility *. Vol.to_float p.volatility
                 *. p.spot *. p.spot *. gamma_condition)
              /. 365.
          in
          {
            stock_delta = Ok (sample delta_condition ld hd wd zd);
            stock_gamma = Ok (sample gamma_condition lg hg wg zg);
            calendar_theta =
              (if theta_event admitted then
                 Error "theta at a valuation event or expiry is unavailable"
               else
                 Ok
                   (sample theta_condition (theta low ld lg) (theta high hd hg)
                      (theta low wd wg) (theta high zd zg)));
            point_price;
          }
      with
      | E.Unresolved reason -> unavailable ("derivative arithmetic: " ^ reason)
      | Stop (Arithmetic_unresolved reason) ->
          unavailable ("derivative arithmetic: " ^ reason)

  let derivative_refinement samples =
    match samples with
    | [ d0; d1; s0; s1; t0; t1; v ] | [ d0; d1; s0; s1; t0; t1; _; _; v ] ->
        let difference a b = abs_float (a.sample_value -. b.sample_value) in
        let sc = (difference s1 s0, difference v s1)
        and tc = (difference t1 t0, difference v t1)
        and dc = (difference d1 d0, difference v d1) in
        let ec =
          match samples with
          | [ _; _; _; _; _; _; e0; e1; _ ] ->
              Some (difference e1 e0, difference v e1)
          | _ -> None
        in
        Some
          {
            space_changes = sc;
            time_changes = tc;
            domain_changes = dc;
            event_changes = ec;
            boundary_half_spread = v.sample_spread;
            observed_sum =
              snd sc +. snd tc +. snd dc +. v.sample_spread
              +. Option.fold ~none:0. ~some:snd ec;
          }
    | [ _ ] -> None
    | _ -> fail "incomplete derivative observations"

  let qualify_greek request samples bump_changes price_indicator method_name =
    let refinement = derivative_refinement samples in
    let final = List.hd (List.rev samples) in
    let arithmetic =
      List.fold_left (fun a s -> float_max a s.sample_arithmetic) 0. samples
    in
    let stencil =
      List.fold_left (fun a s -> float_max a s.sample_stencil) 0. samples
    in
    let small x =
      Float.is_finite x && x >= 0. && x <= request.tolerance /. 8.
    in
    let pair (a, b) = small a && small b in
    let mesh_ok =
      match refinement with
      | None -> true
      | Some r ->
          pair r.space_changes && pair r.time_changes && pair r.domain_changes
          && Option.fold ~none:true ~some:pair r.event_changes
          && small r.boundary_half_spread
    in
    let sum =
      Option.fold ~none:0. ~some:(fun r -> r.observed_sum) refinement
      +. stencil +. arithmetic
      +. Option.fold ~none:0. ~some:snd bump_changes
    in
    if
      not
        (Float.is_finite final.sample_value
        && Float.is_finite price_indicator
        && mesh_ok && small stencil && small arithmetic
        && Option.fold ~none:true ~some:pair bump_changes
        && Float.is_finite sum
        && sum <= request.tolerance /. 2.)
    then
      Greek_accuracy_not_demonstrated
        {
          derivative_refinement = refinement;
          bump_changes;
          stencil_change = stencil;
          arithmetic_indicator = arithmetic;
          amplified_price_indicator = price_indicator;
        }
    else
      Greek_estimate
        {
          value = final.sample_value;
          assurance = Estimated_only;
          requested_tolerance = request.tolerance;
          method_name;
          diagnostics =
            {
              derivative_refinement = refinement;
              bump_changes;
              stencil_change = stencil;
              arithmetic_indicator = arithmetic;
              amplified_price_indicator = price_indicator;
            };
        }

  let analytic_spatial ?curves tick admitted side quantity =
    let p = inputs admitted in
    let cash = greek_cash admitted in
    let no_cash =
      Option.fold ~none:true ~some:(fun c -> Array.length c.dividends = 0) cash
    in
    let all curve predicate =
      Array.for_all
        (fun (_, v) ->
          tick ();
          predicate v)
        curve.segments
    in
    let terminal = p.opens_at = p.time_to_expiry in
    let european_reduction =
      no_cash
      && (terminal
         || side = Side.Call
            &&
            match curves with
            | None -> p.dividend_yield = 0. && p.rate >= 0.
            | Some cs ->
                all cs.yields (( = ) 0.) && all cs.rates (fun r -> r >= 0.))
    in
    if p.spot <= 0. || p.strike <= 0. then
      Error "absorbing-stock/zero-strike Greeks are not qualified"
    else if
      p.time_to_expiry = 0. && no_cash && p.spot <> p.strike
      && quantity <> Theta
    then
      Ok
        (exact
           (match (quantity, side) with
           | Delta, Side.Call when p.spot > p.strike -> 1.
           | Delta, Side.Put when p.spot < p.strike -> -1.
           | _ -> 0.))
    else if (not european_reduction) || p.time_to_expiry = 0. then
      Error "non-smooth or unqualified analytical stopping regime"
    else
      let r, q, a =
        match curves with
        | None ->
            ( E.mul_float (exact p.rate) p.time_to_expiry,
              E.mul_float (exact p.dividend_yield) p.time_to_expiry,
              E.mul_float
                (E.mul
                   (exact (Vol.to_float p.volatility))
                   (exact (Vol.to_float p.volatility)))
                p.time_to_expiry )
        | Some cs ->
            let integrate c f = curve_integral tick c 0. p.time_to_expiry f in
            ( integrate cs.rates exact,
              integrate cs.yields exact,
              integrate cs.vols (fun v -> E.mul (exact v) (exact v)) )
      in
      if E.sign a <> E.Positive then
        Error "zero-variance analytical Greeks are not qualified"
      else
        let discount = E.exp (E.neg q) in
        let x = E.mul (exact p.spot) discount
        and y = E.mul (exact p.strike) (E.exp (E.neg r))
        and root = E.sqrt a in
        let d1 =
          E.div (E.add (E.sub (E.log x) (E.log y)) (E.mul_float a 0.5)) root
        in
        let delta =
          E.mul discount
            (if side = Side.Call then Model_enclosure.Fast.cdf d1
             else E.neg (Model_enclosure.Fast.cdf (E.neg d1)))
        in
        let gamma =
          E.div
            (E.mul discount (Model_enclosure.Fast.pdf d1))
            (E.mul (exact p.spot) root)
        in
        match quantity with
        | Delta -> Ok delta
        | Gamma -> Ok gamma
        | Theta ->
            if theta_event admitted then
              Error "theta at a valuation event or expiry is unavailable"
            else
              let value =
                match curves with
                | None -> european p side
                | Some cs -> piecewise_european tick cs p side
              in
              let v, e = value in
              Ok
                (E.div_float
                   (E.sub
                      (E.sub
                         (E.mul_float (E.add_error (exact v) e) p.rate)
                         (E.mul
                            (E.sub (exact p.rate) (exact p.dividend_yield))
                            (E.mul (exact p.spot) delta)))
                      (E.mul_float
                         (E.mul
                            (E.mul
                               (exact (Vol.to_float p.volatility))
                               (exact (Vol.to_float p.volatility)))
                            (E.mul (E.mul (exact p.spot) (exact p.spot)) gamma))
                         0.5))
                   365.)
        | Vega | Rho -> Error "use explicit parallel perturbations"

  let shift_greek ?curves ~tick admitted quantity h =
    let shift x =
      tick ();
      let s = E.add (exact x) (exact h) in
      let v = centre s in
      if (not (Float.is_finite v)) || E.sign (E.sub s (exact v)) <> E.Zero then
        raise (E.Unresolved "parallel shift is not exactly representable");
      if quantity = Vega && v < 0. then
        raise (E.Unresolved "volatility shift outside nonnegative domain");
      v
    in
    let p = inputs admitted in
    let p =
      match quantity with
      | Rho -> { p with rate = shift p.rate }
      | Vega -> (
          match Vol.lognormal (shift (Vol.to_float p.volatility)) with
          | Ok v -> { p with volatility = v }
          | Error _ -> raise (E.Unresolved "volatility shift"))
      | _ -> p
    in
    let admitted =
      match admitted with
      | Admitted _ -> Admitted p
      | With_cash (_, c) -> With_cash (p, c)
      | Bermudan (_, c, ds) -> Bermudan (p, c, ds)
    in
    let curves =
      Option.map
        (fun cs ->
          let shifted c =
            {
              c with
              initial = shift c.initial;
              changes = Array.map (fun (t, v) -> (t, shift v)) c.changes;
              segments = Array.map (fun (t, v) -> (t, shift v)) c.segments;
            }
          in
          match quantity with
          | Rho -> { cs with rates = shifted cs.rates }
          | Vega -> { cs with vols = shifted cs.vols }
          | _ -> cs)
        curves
    in
    (admitted, curves)

  let greeks_with_curves ?curves ?(cancel = fun () -> false) cfg requests
      admitted side =
    try
      if cancel () then raise (Stop Cancelled);
      let solves =
        1
        + 6
          * List.length
              (List.filter
                 (fun (r : greek_request) ->
                   r.quantity = Vega || r.quantity = Rho)
                 requests)
      in
      let metadata =
        match curves with
        | None -> 0
        | Some cs ->
            Array.length cs.rates.changes
            + Array.length cs.yields.changes
            + Array.length cs.vols.changes
            + 3
      in
      if
        cfg.limits.max_workspace_bytes < 131072
        || metadata > (cfg.limits.max_workspace_bytes - 131072) / 1024
      then
        raise (Stop (Resource_limit "Greek observation/perturbation workspace"));
      let partitions = solves + 1 in
      let limits =
        {
          cfg.limits with
          max_steps = cfg.limits.max_steps / partitions;
          max_policy_solves = cfg.limits.max_policy_solves / partitions;
          max_row_visits = cfg.limits.max_row_visits / partitions;
          max_workspace_bytes =
            cfg.limits.max_workspace_bytes - 65536 - (1024 * metadata);
        }
      in
      if
        limits.max_steps = 0
        || limits.max_policy_solves = 0
        || limits.max_row_visits = 0
      then raise (Stop (Resource_limit "Greek request work partition"));
      let cfg = { cfg with limits } in
      let extra_visits = ref 0 in
      let tick () =
        if cancel () then raise (Stop Cancelled);
        incr extra_visits;
        if !extra_visits > limits.max_row_visits then
          raise (Stop (Resource_limit "Greek analytic visits"))
      in
      (* This pool belongs to this one admitted contract, side and fixed
         configuration. shift_greek preserves stock/strike, event/exercise
         objects and horizons. Rate/yield identities and the original slab
         partition must also match: rho must never borrow vega's boundaries. *)
      let boundary_reuse =
        if List.exists (fun (r : greek_request) -> r.quantity = Vega) requests
        then Some (ref None)
        else None
      in
      let original = inputs admitted and original_curves = curves in
      let run ?curves a =
        let observations = ref [] in
        let observe c x low high =
          observations := observe_greeks a side c x low high :: !observations
        in
        let p = inputs a in
        let same_boundary_inputs =
          Int64.bits_of_float p.rate = Int64.bits_of_float original.rate
          && Int64.bits_of_float p.dividend_yield
             = Int64.bits_of_float original.dividend_yield
          &&
          match (curves, original_curves) with
          | None, None -> true
          | Some cs, Some original ->
              cs.rates == original.rates
              && cs.yields == original.yields
              && cs.knots == original.knots
          | _ -> false
        in
        let reuse =
          if same_boundary_inputs then boundary_reuse
          else (
            (* Do not retain one solve's cache while an incompatible solve
               spends that same surplus workspace on its own preparation. *)
            Option.iter (fun reuse -> reuse := None) boundary_reuse;
            None)
        in
        match
          price_with_curves ?curves ~observe ?boundary_reuse:reuse ~cancel cfg a
            side
        with
        | Error (Cancelled as f) | Error (Resource_limit _ as f) ->
            raise (Stop f)
        | Error f -> Error f
        | Ok price -> Ok (price, List.rev !observations)
      in
      match run ?curves admitted with
      | Error f -> Error f
      | Ok (price, observations) ->
          let perturbations = ref [] in
          let price_indicator (p : estimated_price) =
            Option.fold ~none:0. ~some:(fun r -> r.observed_sum) p.refinement
            +. p.maximum_roundoff_indicator +. p.boundary_arithmetic_indicator
          in
          let sample_price ((p : estimated_price), observations) =
            match observations with
            | [] ->
                [
                  {
                    sample_value = p.value;
                    sample_spread = 0.;
                    sample_stencil = 0.;
                    sample_arithmetic =
                      p.maximum_roundoff_indicator
                      +. p.boundary_arithmetic_indicator;
                    sample_condition = 1.;
                  };
                ]
            | _ -> List.map (fun o -> o.point_price) observations
          in
          let outcome (request : greek_request) =
            try
              match request.quantity with
              | Delta | Gamma | Theta -> (
                  let samples =
                    match observations with
                    | [] -> (
                        match
                          analytic_spatial ?curves tick admitted side
                            request.quantity
                        with
                        | Error e -> Error e
                        | Ok x ->
                            let v, e = enclosed x in
                            Ok
                              [
                                {
                                  sample_value = v;
                                  sample_spread = 0.;
                                  sample_stencil = 0.;
                                  sample_arithmetic = e;
                                  sample_condition = 0.;
                                };
                              ])
                    | _ ->
                        let selected =
                          List.map
                            (fun o ->
                              match request.quantity with
                              | Delta -> o.stock_delta
                              | Gamma -> o.stock_gamma
                              | _ -> o.calendar_theta)
                            observations
                        in
                        List.fold_right
                          (fun s acc ->
                            match (s, acc) with
                            | Ok s, Ok xs -> Ok (s :: xs)
                            | Error e, _ | _, Error e -> Error e)
                          selected (Ok [])
                  in
                  match samples with
                  | Error e -> Greek_unavailable e
                  | Ok samples ->
                      let amplification =
                        List.fold_left
                          (fun m s -> float_max m s.sample_condition)
                          0. samples
                      in
                      qualify_greek request samples None
                        (amplification *. price_indicator price)
                        "refined-spatial-or-analytic-v1")
              | Vega | Rho -> (
                  let p = inputs admitted in
                  let zero_vol =
                    match curves with
                    | None -> Vol.to_float p.volatility = 0.
                    | Some cs ->
                        Array.exists (fun (_, v) -> v = 0.) cs.vols.segments
                  in
                  if request.quantity = Vega && zero_vol then
                    Greek_unavailable
                      "ordinary parallel vega unavailable at a zero volatility \
                       level"
                  else if p.time_to_expiry = 0. then
                    Greek_unavailable
                      "expiry parameter derivatives are not qualified"
                  else
                    let h = Option.get request.bump in
                    let estimates = ref [] and amplified = ref 0. in
                    for scale = 0 to 2 do
                      tick ();
                      let h = Float.ldexp h (-scale) in
                      let shifted amount =
                        let a, cs =
                          shift_greek ?curves ~tick admitted request.quantity
                            amount
                        in
                        match run ?curves:cs a with
                        | Error f -> raise (Stop f)
                        | Ok (p, os) ->
                            perturbations :=
                              {
                                quantity = request.quantity;
                                shift = amount;
                                price = p;
                              }
                              :: !perturbations;
                            (p, os)
                      in
                      let minus = shifted (-.h) in
                      let plus = shifted h in
                      amplified :=
                        float_max !amplified
                          ((price_indicator (fst minus)
                           +. price_indicator (fst plus))
                          /. (2. *. h));
                      let a = sample_price minus and b = sample_price plus in
                      let original = sample_price (price, observations) in
                      if
                        List.length a <> List.length b
                        || List.length a <> List.length original
                      then
                        raise
                          (E.Unresolved
                             "perturbation changes analytical/numerical route");
                      let samples =
                        List.map2
                          (fun (a, original) b ->
                            let v, e =
                              enclosed
                                (E.div_float
                                   (E.sub (exact b.sample_value)
                                      (exact a.sample_value))
                                   (2. *. h))
                            in
                            let slope_difference, slope_arithmetic =
                              enclosed
                                (E.div_float
                                   (E.add
                                      (E.sub (exact b.sample_value)
                                         (exact original.sample_value))
                                      (E.sub (exact a.sample_value)
                                         (exact original.sample_value)))
                                   h)
                            in
                            {
                              sample_value = v;
                              sample_spread =
                                (a.sample_spread +. b.sample_spread) /. (2. *. h);
                              sample_stencil = abs_float slope_difference;
                              sample_arithmetic =
                                e +. slope_arithmetic
                                +. (a.sample_arithmetic +. b.sample_arithmetic
                                   +. (2. *. original.sample_arithmetic))
                                   /. h;
                              sample_condition = 0.;
                            })
                          (List.combine a original) b
                      in
                      estimates := samples :: !estimates
                    done;
                    match !estimates with
                    | [ fine; middle; coarse ] ->
                        if
                          List.length fine <> List.length middle
                          || List.length middle <> List.length coarse
                        then
                          raise
                            (E.Unresolved
                               "bump refinement changes analytical/numerical \
                                route");
                        let max_change a b =
                          List.fold_left2
                            (fun m a b ->
                              float_max m
                                (abs_float (a.sample_value -. b.sample_value)))
                            0. a b
                        in
                        qualify_greek request fine
                          (Some
                             (max_change middle coarse, max_change fine middle))
                          !amplified "parallel-central-refinement-v1"
                    | _ -> assert false)
            with
            | E.Unresolved e -> Greek_unavailable e
            | Stop (Cancelled as f) | Stop (Resource_limit _ as f) ->
                raise (Stop f)
            | Stop f -> Greek_failure f
          in
          let greeks =
            List.map
              (fun (r : greek_request) -> (r.quantity, outcome r))
              requests
          in
          if cancel () then raise (Stop Cancelled);
          Ok { price; greeks; perturbation_prices = List.rev !perturbations }
    with
    | Stop f -> Error f
    | E.Unresolved e -> Error (Arithmetic_unresolved e)

  let greeks ?cancel cfg requests admitted side =
    greeks_with_curves ?cancel cfg requests admitted side

  module Implied_volatility = struct
    module B = Enclosure

    type no_solution =
      | Below_immediate_payoff
      | Above_global_cap
      | Incompatible_constant_price

    type independent = Expiry | Absorbing_stock | Zero_strike
    type range_side = Below | Above

    type error =
      | Invalid_quote
      | Invalid_configuration of string
      | Unsupported_cash_put
      | No_solution of no_solution
      | Non_identifiable of independent
      | Estimated_outside_search_range of range_side
      | Price_uncertainty_or_plateau
      | Inconsistent_prices
      | Pricing_failed of failure
      | Evaluation_limit
      | Unrepresentable_progress
      | Cancelled

    type quote = float

    let quote x =
      if Float.is_finite x && x >= 0. then Ok x else Error Invalid_quote

    type settings = {
      pricing : configuration;
      lower : Vol.lognormal Vol.t;
      upper : Vol.lognormal Vol.t;
      width : float;
      max_evaluations : int;
    }

    let configure ~pricing ~lower ~upper ~width ~max_evaluations =
      if Vol.to_float lower >= Vol.to_float upper then
        Error
          (Invalid_configuration "strictly increasing volatility range required")
      else if (not (Float.is_finite width)) || width <= 0. then
        Error
          (Invalid_configuration "positive finite volatility width required")
      else if max_evaluations < 2 then
        Error (Invalid_configuration "at least two price evaluations required")
      else Ok { pricing; lower; upper; width; max_evaluations }

    type observation = {
      volatility : Vol.lognormal Vol.t;
      price : estimated_price;
      uncertainty_indicator : float;
    }

    type estimated_interval = {
      lower : observation;
      upper : observation;
      requested_width : float;
      evaluations : int;
      assurance : assurance;
    }

    exception Abort of error
    exception Callback_error of exn

    let stop e = raise (Abort e)
    let exact = B.exact

    let positive_part x =
      match B.sign x with
      | B.Positive -> x
      | B.Zero | B.Negative -> exact 0.
      | B.Indeterminate -> raise (B.Unresolved "inverse payoff sign")

    let indicator (p : estimated_price) =
      let refinement =
        Option.fold ~none:0. ~some:(fun r -> r.observed_sum) p.refinement
      in
      let x =
        B.add (exact refinement)
          (B.add
             (exact p.maximum_roundoff_indicator)
             (exact p.boundary_arithmetic_indicator))
      in
      let error = B.error_of_float x x.hi in
      let result =
        if error = 0. then x.hi else Float.next_after (x.hi +. error) infinity
      in
      if (not (Float.is_finite result)) || result < 0. then
        raise (B.Unresolved "inverse price indicator");
      result

    let edge (o : observation) sign =
      B.add (exact o.price.value) (exact (sign *. o.uncertainty_indicator))

    let classify quote o =
      if B.compare_float (edge o 1.) quote = B.Negative then -1
      else if B.compare_float (edge o (-1.)) quote = B.Positive then 1
      else 0

    let ordered a b =
      if B.sign (B.sub (edge a (-1.)) (edge b 1.)) = B.Positive then
        stop Inconsistent_prices

    let replace_volatility admitted volatility =
      match admitted with
      | Admitted p -> Admitted { p with volatility }
      | With_cash (p, cash) -> With_cash ({ p with volatility }, cash)
      | Bermudan (p, cash, dates) ->
          Bermudan ({ p with volatility }, cash, dates)

    let solve ?(cancel = fun () -> false) cfg admitted side quote =
      let cancel () = try cancel () with e -> raise (Callback_error e) in
      let checkpoint () = if cancel () then stop Cancelled in
      try
        checkpoint ();
        let p = inputs admitted in
        let cash =
          match admitted with
          | Admitted _ -> None
          | With_cash (_, c) -> Some c
          | Bermudan (_, c, _) -> c
        in
        if side = Side.Put && Option.is_some cash then stop Unsupported_cash_put;
        let limits = cfg.pricing.limits in
        if limits.max_workspace_bytes < 65536 then
          stop (Pricing_failed (Resource_limit "inverse metadata workspace"));
        (* A mathematical cap is optional evidence, never a rounded substitute.
           Failure to enclose it cannot establish absence of a root. *)
        (try
           let amount, rate =
             if side = Side.Call then (p.spot, p.dividend_yield)
             else (p.strike, p.rate)
           in
           let exponent =
             B.mul (exact (max 0. (-.rate))) (exact p.time_to_expiry)
           in
           let cap = B.mul (exact amount) (B.exp exponent) in
           if B.compare_float cap quote = B.Negative then
             stop (No_solution Above_global_cap)
         with B.Unresolved _ -> ());
        (if cash = None && p.opens_at = 0. then
           let difference = B.sub (exact p.spot) (exact p.strike) in
           let payoff =
             if side = Side.Call then difference else B.neg difference
           in
           if B.compare_float payoff quote = B.Positive then
             stop (No_solution Below_immediate_payoff));
        let constant =
          if p.time_to_expiry = 0. then (
            let stock = ref (exact p.spot) in
            (match cash with
            | Some c
              when c.valuation_side = Before_cash && c.opening_side = After_cash
              ->
                let total = ref (exact 0.) in
                Array.iteri
                  (fun i (d : dividend) ->
                    checkpoint ();
                    if i >= limits.max_row_visits then
                      stop
                        (Pricing_failed
                           (Resource_limit "inverse expiry cash rows"));
                    total := B.add !total (exact d.amount))
                  c.dividends;
                stock := positive_part (B.sub !stock !total)
            | _ -> ());
            let difference = B.sub !stock (exact p.strike) in
            Some
              ( Expiry,
                positive_part
                  (if side = Side.Call then difference else B.neg difference) ))
          else if p.spot = 0. then
            if side = Side.Call then Some (Absorbing_stock, exact 0.)
            else
              let t = if p.rate >= 0. then p.opens_at else p.time_to_expiry in
              Some
                ( Absorbing_stock,
                  B.mul (exact p.strike)
                    (B.exp (B.mul (exact (-.p.rate)) (exact t))) )
          else if p.strike = 0. && cash = None then
            if side = Side.Put then Some (Zero_strike, exact 0.)
            else
              let t =
                if p.dividend_yield >= 0. then p.opens_at else p.time_to_expiry
              in
              Some
                ( Zero_strike,
                  B.mul (exact p.spot)
                    (B.exp (B.mul (exact (-.p.dividend_yield)) (exact t))) )
          else None
        in
        (match constant with
        | Some (reason, value) -> (
            checkpoint ();
            match B.compare_float value quote with
            | B.Zero -> stop (Non_identifiable reason)
            | B.Positive | B.Negative ->
                stop (No_solution Incompatible_constant_price)
            | B.Indeterminate -> stop Price_uncertainty_or_plateau)
        | None -> ());
        let limits =
          {
            limits with
            max_steps = limits.max_steps / cfg.max_evaluations;
            max_policy_solves = limits.max_policy_solves / cfg.max_evaluations;
            max_row_visits = limits.max_row_visits / cfg.max_evaluations;
            max_workspace_bytes = limits.max_workspace_bytes - 65536;
          }
        in
        if
          limits.max_steps = 0
          || limits.max_policy_solves = 0
          || limits.max_row_visits = 0
        then stop (Pricing_failed (Resource_limit "inverse work partition"));
        let pricing = { cfg.pricing with limits } and evaluations = ref 0 in
        let evaluate volatility =
          checkpoint ();
          if !evaluations >= cfg.max_evaluations then stop Evaluation_limit;
          incr evaluations;
          match
            price ~cancel pricing (replace_volatility admitted volatility) side
          with
          | Error Cancelled -> stop Cancelled
          | Error e -> stop (Pricing_failed e)
          | Ok price ->
              { volatility; price; uncertainty_indicator = indicator price }
        in
        let midpoint a b =
          let lo = Vol.to_float a.volatility
          and hi = Vol.to_float b.volatility in
          let mid = lo +. ((hi -. lo) *. 0.5) in
          if not (lo < mid && mid < hi) then stop Unrepresentable_progress;
          match Vol.lognormal mid with
          | Ok v -> v
          | Error _ -> stop Unrepresentable_progress
        in
        let sample a b =
          let m = evaluate (midpoint a b) in
          ordered a m;
          ordered m b;
          m
        in
        let rec search lower upper =
          checkpoint ();
          let distance =
            B.sub
              (exact (Vol.to_float upper.volatility))
              (exact (Vol.to_float lower.volatility))
          in
          match B.compare_float distance cfg.width with
          | B.Zero | B.Negative ->
              if classify quote lower <> -1 || classify quote upper <> 1 then
                stop Price_uncertainty_or_plateau;
              {
                lower;
                upper;
                requested_width = cfg.width;
                evaluations = !evaluations;
                assurance = Estimated_only;
              }
          | B.Positive | B.Indeterminate -> (
              let mid = sample lower upper in
              match classify quote mid with
              | -1 -> search mid upper
              | 1 -> search lower mid
              | _ ->
                  let left = sample lower mid in
                  if classify quote left = 1 then search lower left
                  else
                    let right = sample mid upper in
                    if classify quote right = -1 then search right upper
                    else
                      let lo =
                        if classify quote left = -1 then left else lower
                      in
                      let hi =
                        if classify quote right = 1 then right else upper
                      in
                      if lo == lower && hi == upper then
                        stop Price_uncertainty_or_plateau;
                      search lo hi)
        in
        let lower = evaluate cfg.lower in
        let upper = evaluate cfg.upper in
        ordered lower upper;
        let a = classify quote lower and b = classify quote upper in
        if a = 1 then stop (Estimated_outside_search_range Below);
        if b = -1 then stop (Estimated_outside_search_range Above);
        if a <> -1 || b <> 1 then stop Price_uncertainty_or_plateau;
        let result = search lower upper in
        checkpoint ();
        Ok result
      with
      | Callback_error e -> raise e
      | Abort e -> Error e
      | B.Unresolved s -> Error (Pricing_failed (Arithmetic_unresolved s))
  end

  module Piecewise = struct
    module Rate = struct
      type t = curve

      let create = make_curve
      let horizon c = c.horizon
      let initial c = c.initial
      let changes c = Array.copy c.changes
    end

    module Yield = struct
      type t = curve

      let create = make_curve
      let horizon c = c.horizon
      let initial c = c.initial
      let changes c = Array.copy c.changes
    end

    module Volatility = struct
      type t = curve

      let create ~horizon ~initial ~changes =
        make_curve ~horizon ~initial:(Vol.to_float initial)
          ~changes:(Array.map (fun (t, v) -> (t, Vol.to_float v)) changes)

      let horizon c = c.horizon

      let typed v =
        match Vol.lognormal v with Ok v -> v | Error _ -> assert false

      let initial c = typed c.initial
      let changes c = Array.map (fun (t, v) -> (t, typed v)) c.changes
    end

    type constant_inputs = inputs

    type inputs = {
      spot : float;
      strike : float;
      rate : Rate.t;
      dividend_yield : Yield.t;
      time_to_expiry : float;
      opens_at : float;
      volatility : Volatility.t;
    }

    type constant_admitted = admitted

    type admitted = {
      original : inputs;
      base : constant_admitted;
      curves : coefficient_curves option;
    }

    let admit_base admit (p : inputs) =
      if
        p.rate.horizon <> p.time_to_expiry
        || p.dividend_yield.horizon <> p.time_to_expiry
        || p.volatility.horizon <> p.time_to_expiry
      then Error (Invalid_input "coefficient coverage differs from expiry")
      else
        let constant : constant_inputs =
          {
            spot = p.spot;
            strike = p.strike;
            rate = p.rate.initial;
            dividend_yield = p.dividend_yield.initial;
            time_to_expiry = p.time_to_expiry;
            opens_at = p.opens_at;
            volatility = Volatility.initial p.volatility;
          }
        in
        match admit constant with
        | Error e -> Error e
        | Ok base ->
            let cs = [ p.rate; p.dividend_yield; p.volatility ] in
            let curves =
              if List.for_all (fun c -> Array.length c.segments = 1) cs then
                None
              else
                let knots =
                  List.sort_uniq Float.compare
                    (List.concat_map
                       (fun c ->
                         Array.to_list
                           (Array.sub c.segments 1
                              (Array.length c.segments - 1))
                         |> List.map fst)
                       cs)
                in
                Some
                  {
                    rates = p.rate;
                    yields = p.dividend_yield;
                    vols = p.volatility;
                    knots;
                  }
            in
            Ok { original = p; base; curves }

    let admit p = admit_base admit p
    let admit_cash p cash = admit_base (fun q -> admit_cash q cash) p

    let admit_bermudan ?cash p dates =
      admit_base (fun q -> admit_bermudan ?cash q dates) p

    let inputs p = p.original
    let cash_specification p = cash_specification p.base
    let exercise_schedule p = exercise_schedule p.base

    let price ?cancel ?exercise_regions ?premium cfg p side =
      price_with_curves ?curves:p.curves ?cancel ?exercise_regions ?premium cfg
        p.base side

    let greeks ?cancel cfg requests p side =
      greeks_with_curves ?curves:p.curves ?cancel cfg requests p.base side
  end
end
