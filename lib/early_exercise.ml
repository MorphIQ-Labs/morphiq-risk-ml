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

  type admitted =
    | Admitted of inputs
    | With_cash of inputs * cash_specification

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
          (fun d ->
            if
              (not (Float.is_finite d.time && Float.is_finite d.amount))
              || d.time < !previous || d.time > p.time_to_expiry
              || d.amount < 0.
            then valid := false;
            previous := d.time)
          cash.dividends;
        let event t = Array.exists (fun d -> d.time = t) cash.dividends in
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

  let inputs = function Admitted p | With_cash (p, _) -> p

  let cash_specification = function
    | Admitted _ -> None
    | With_cash (_, cash) ->
        Some { cash with dividends = Array.copy cash.dividends }

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
      (fun i d ->
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

  (* The price request owns preparation for one stock-grid key. Payoff and
     spatial bands depend only on that grid, the fixed model and option side;
     time steps, boundary choice and cash interpolation do not alter them. *)
  let solver_pair ?cash ~prepared c p side x time_steps capture =
   fun upper_boundary ->
    check c;
    let n = Array.length x and sigma = Vol.to_float p.volatility in
    let arr () = Array.make n 0. in
    let left, right, g, reused, switched =
      match !prepared with
      | None -> (arr (), arr (), arr (), false, 0)
      | Some (left, right, g, switched) ->
          if
            Array.length left <> n
            || Array.length right <> n
            || Array.length g <> n
          then fail "prepared spatial grid mismatch";
          (left, right, g, true, switched)
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
    (if reused then (
       (* A logical stencil-row visit remains a visit when loading a prepared
         coefficient. Retain limits/cancellation and switched-row diagnostics. *)
       for _ = 1 to n - 2 do
         tick c
       done;
       c.switched <- c.switched + switched)
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
             (E.div numerator_m (E.mul hm sum), E.div numerator_p (E.mul hp sum))
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
       prepared := Some (left, right, g, c.switched - switched_before));
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
    let slab earlier later obstacle =
      if earlier < later then (
        let width = E.sub (exact later) (exact earlier) in
        let h_e = E.div_float width (float time_steps) in
        let h = finite "time increment" (centre h_e) in
        if h <= 0. then fail "collapsed time step";
        if h *. float_max (-.p.rate) 0. > 0.5 then
          fail "negative-rate matrix margin";
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
            if t >= p.opens_at then exact 0. else E.sub (exact p.opens_at) t_e
          in
          let zero =
            if side = Side.Call then 0.
            else
              boundary c
                (E.mul (exact p.strike)
                   (exp_product (-.p.rate)
                      (if p.rate < 0. then remaining else wait)))
          in
          let top =
            if upper_boundary then
              boundary c
                (E.mul
                   (exact (if side = Side.Call then x.(n - 1) else p.strike))
                   (exp_product
                      (float_max
                         (if side = Side.Call then -.p.dividend_yield
                          else -.p.rate)
                         0.)
                      remaining))
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
    (match cash with
    | None ->
        slab p.opens_at p.time_to_expiry true;
        slab 0. p.opens_at false
    | Some (spec, events, mapping_grid) ->
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
        let exercise phase time =
          if eligible p spec time phase then
            for i = 0 to n - 1 do
              tick c;
              v.(i) <- float_max v.(i) g.(i)
            done
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
              c.event_applications <- c.event_applications + 1;
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

  let price ?(cancel = fun () -> false) ?(exercise_regions = false)
      ?(premium = false) cfg admitted side =
    let p = inputs admitted in
    let cash =
      match admitted with
      | Admitted _ -> None
      | With_cash (_, spec) ->
          if Array.length spec.dividends = 0 then None else Some spec
    in
    try
      if cancel () then raise (Stop Cancelled);
      if cfg.limits.max_workspace_bytes < 65536 then
        raise (Stop (Resource_limit "analytic workspace bytes"));
      let cash_visits = ref 0 in
      let events =
        match cash with
        | None -> []
        | Some spec -> prepare_cash cfg cancel cash_visits spec
      in
      let immediate =
        match cash with
        | None -> p.opens_at = 0.
        | Some spec -> eligible p spec 0. spec.valuation_side
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
              let ev, ee = european p side in
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
          work;
          exercise_regions = regions;
          early_exercise_premium = premium_result;
        }
      in
      let analytical =
        match cash with
        | None -> analytic p side
        | Some spec when Array.length spec.dividends = 0 -> analytic p side
        | Some spec -> cash_analytic cfg cancel cash_visits p spec events side
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
          check_workspace c;
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

          let fine_time = 4 * cfg.time_steps in
          (* Single-entry, request-owned cache. grid is deterministic in the
             fixed inputs/configuration plus (level, domain). Drop the previous
             preparation before constructing a different grid. *)
          let spatial = ref None in
          let run ?(mapping_level = 2) level domain time capture =
            let prepared =
              match !spatial with
              | Some (l, d, prepared) when l = level && d = domain -> prepared
              | _ ->
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
            let solve = solver_pair ?cash ~prepared c p side x time capture in
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
             let ev, ee = european p side in
             if value +. sum +. c.boundary_error < ev -. ee then
               fail
                 "matching European lower bound beyond refinement diagnostics");
          let regions =
            try
              if not exercise_regions then Not_requested
              else if not immediate then
                Unavailable "exercise window has not opened"
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
            (make_result "backward-Euler-policy-v1" value 0. (Some refinement)
               work c.residual c.roundoff c.boundary_error regions
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
end
