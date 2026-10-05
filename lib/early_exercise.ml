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

  let eta = Float.next_after 0. infinity

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

  let tick c =
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

  let boundary c x =
    let v, e = enclosed x in
    c.boundary_error <- float_max c.boundary_error e;
    if e > c.local then fail "boundary arithmetic resolution";
    nonnegative "boundary value" v

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

  (* Cache only successful scalar boundary values, not enclosures. Every hit
     follows a previous boundary check in this same request, whose local
     allowance is fixed and boundary_error only increases. Slab keys retain
     original words; rounded time coordinates are not dependency identities.
     A 256-byte entry charge covers the list/tuple/key/array headers and boxed
     words on the supported 64-bit runtime; payload is 8 bytes per step. *)
  let boundary_values ?top ~max_steps cache earlier later next_exercise
      time_steps =
    let remaining, entries = !cache in
    if
      (remaining = 0 && entries = [])
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
      match List.assoc_opt key entries with
      | Some values -> Some values
      | None ->
          if remaining < 256 || time_steps > (remaining - 256) / 8 then None
          else
            let values = Array.make time_steps nan in
            cache :=
              (remaining - 256 - (8 * time_steps), (key, values) :: entries);
            Some values

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
        let remaining, boundaries = !boundary_cache in
        if curves <> None && remaining >= 256 && n <= (remaining - 256) / 16
        then (
          let charge = 256 + (16 * n) in
          let used, entries = !stencils in
          stencils :=
            ( used + charge,
              (key p, (Array.copy left, Array.copy right, switched)) :: entries
            );
          boundary_cache := (remaining - charge, boundaries))
    in
    prepare p reused switched;
    let current_key = ref (key p) in
    let residual obstacle =
      let worst = ref 0. and worst_row = ref 0 and indicator = ref 0. in
      for i = 1 to n - 2 do
        tick c;
        (* Original unfactored bands; explicit FMA differs from elimination's
           accumulation. No product complementarity test. *)
        let pvalue =
          Float.fma lo.(i)
            v.(i - 1)
            (Float.fma diag.(i) v.(i) (Float.fma hi.(i) v.(i + 1) (-.rhs.(i))))
        in
        let e = v.(i) -. g.(i) in
        let r =
          if obstacle then
            float_max
              (abs_float (float_min pvalue e))
              (float_max (-.pvalue) (-.e))
          else abs_float pvalue
        in
        ignore (finite "original residual" r);
        if r > !worst then (
          worst := r;
          worst_row := i);
        let magnitude =
          abs_float (lo.(i) *. v.(i - 1))
          +. abs_float (diag.(i) *. v.(i))
          +. abs_float (hi.(i) *. v.(i + 1))
          +. abs_float rhs.(i)
          +. abs_float v.(i)
          +. abs_float g.(i)
        in
        let screen =
          finite "residual roundoff screen"
            ((0x1p-48 *. magnitude) +. (32. *. eta))
        in
        indicator := float_max !indicator screen
      done;
      c.roundoff <- float_max c.roundoff !indicator;
      if !indicator > c.local /. 4. then fail "residual roundoff resolution";
      (!worst, !worst_row)
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
              let cached =
                match zero_values with None -> nan | Some vs -> vs.(j - 1)
              in
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
                      boundary c (E.mul (exact p.strike) (E.exp exponent))
                  | None ->
                      boundary c
                        (E.mul (exact p.strike)
                           (exp_product (-.p.rate)
                              (if p.rate < 0. then remaining else wait)))
                in
                (match zero_values with
                | None -> ()
                | Some vs -> vs.(j - 1) <- value);
                value
          in
          let top =
            if upper_boundary then (
              let cached =
                match top_values with None -> nan | Some vs -> vs.(j - 1)
              in
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
                  boundary c
                    (E.mul
                       (exact
                          (if side = Side.Call then x.(n - 1) else p.strike))
                       factor)
                in
                (match top_values with
                | None -> ()
                | Some vs -> vs.(j - 1) <- value);
                value)
            else if obstacle then g.(n - 1)
            else 0.
          in
          v.(0) <- zero;
          v.(n - 1) <- top;
          for i = 1 to n - 2 do
            tick c;
            lo.(i) <- -.h *. left.(i);
            hi.(i) <- -.h *. right.(i);
            diag.(i) <- 1. +. (h *. (left.(i) +. right.(i) +. p.rate));
            rhs.(i) <- v.(i);
            let margin =
              finite "assembled matrix margin" (diag.(i) +. lo.(i) +. hi.(i))
            in
            if margin < 0.25 || diag.(i) <= 0. then
              fail "lost binary64 matrix dominance"
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

  let price_with_curves ?curves ?(cancel = fun () -> false)
      ?(exercise_regions = false) ?(premium = false) cfg admitted side =
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
          let boundary_cache = ref (cache_bytes, []) in
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
                  let remaining, boundaries = !boundary_cache in
                  boundary_cache := (remaining + used, boundaries);
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
                ~boundary_cache c p side x time capture
            in
            let low, vl = solve false in
            let high, vh = solve true in
            if high < low then fail "reversed boundary pair";
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
  end
end
