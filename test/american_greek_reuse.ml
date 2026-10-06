open Morphiq_risk
module A = Early_exercise.Bsm
module P = A.Piecewise

let get = function Ok x -> x | Error _ -> failwith "reuse control refused"
let expect message ok = if not ok then failwith message
let sigma x = get (Vol.lognormal x)

let inputs rate_shift vol_shift =
  P.
    {
      spot = 100.;
      strike = 100.;
      opens_at = 0.;
      time_to_expiry = 1.;
      rate =
        get
          (Rate.create ~horizon:1. ~initial:(0.0625 +. rate_shift)
             ~changes:[| (0.5, -0.125 +. rate_shift) |]);
      dividend_yield =
        get
          (Yield.create ~horizon:1. ~initial:0.03125
             ~changes:[| (0.5, 0.0625) |]);
      volatility =
        get
          (Volatility.create ~horizon:1.
             ~initial:(sigma (0.25 +. vol_shift))
             ~changes:[| (0.5, sigma (0.375 +. vol_shift)) |]);
    }

let limits workspace parts =
  A.
    {
      max_nodes = 512;
      max_steps = parts * 32768;
      max_policy_solves = parts * 262144;
      max_row_visits = parts * 100000000;
      max_workspace_bytes = workspace;
      policy_iterations = 64;
    }

let config workspace parts =
  get
    (A.configure ~tolerance:10. ~space_cells:32 ~time_steps:32
       ~domain_expansions:2 ~limits:(limits workspace parts))

let requests order =
  get
    (A.configure_greeks
       (List.map
          (fun q -> get (A.request_greek ~bump:0x1p-10 ~tolerance:100. q))
          order))

let admit cash rate vol =
  let p = inputs rate vol in
  if cash then
    get
      (P.admit_cash p
         A.
           {
             valuation_side = Regular;
             opening_side = Regular;
             expiry_side = Regular;
             dividends = [| { time = 0.5; amount = 5. } |];
           })
  else get (P.admit p)

let price_fields (p : A.estimated_price) =
  (* Greek observers charge extra logical visits. Every other price field must
     describe the identical original-input price, whether evaluated alone or
     as an identified perturbation. Full row-count replay is qualified too. *)
  ( p.value,
    p.assurance,
    p.method_name,
    p.requested_tolerance,
    p.refinement,
    p.mapping,
    p.maximum_residual,
    p.maximum_roundoff_indicator,
    p.boundary_arithmetic_indicator,
    { p.work with row_visits = 0 },
    p.exercise_regions,
    p.early_exercise_premium )

let check cash =
  let admitted = admit cash 0. 0. in
  let original = P.inputs admitted in
  let cfg = config 2097152 14 in
  let result =
    get (P.greeks cfg (requests [ A.Vega; A.Rho ]) admitted Side.Put)
  in
  expect "all identified perturbations available"
    (List.length result.perturbation_prices = 12);
  (* Two prices per coordinate exercise both signs and dependency changes.
     The full frozen campaign covers all bump/refinement combinations. *)
  List.iter
    (fun (p : A.perturbation_price) ->
      if abs_float p.shift = 0x1p-10 then
        let r, v =
          if p.quantity = A.Rho then (p.shift, 0.) else (0., p.shift)
        in
        let direct =
          get
            (P.price
               (config (2097152 - 65536 - (6 * 1024)) 1)
               (admit cash r v) Side.Put)
        in
        expect "perturbation price agrees with independent cold request"
          (price_fields direct = price_fields p.price))
    result.perturbation_prices;
  let reverse =
    get (P.greeks cfg (requests [ A.Rho; A.Vega ]) admitted Side.Put)
  in
  expect "request order cannot alter base price" (reverse.price = result.price);
  List.iter
    (fun (q, g) ->
      expect "request order cannot alter Greek" (List.assoc q reverse.greeks = g))
    result.greeks;
  let find (p : A.perturbation_price) =
    List.find
      (fun (x : A.perturbation_price) ->
        x.quantity = p.quantity && x.shift = p.shift)
      reverse.perturbation_prices
  in
  List.iter
    (fun p -> expect "request order cannot alter perturbed price" (p = find p))
    result.perturbation_prices;
  expect "cache cannot mutate original input" (P.inputs admitted = original);
  (if not cash then
     let small =
       get
         (P.greeks (config 408000 14)
            (requests [ A.Vega; A.Rho ])
            admitted Side.Put)
     in
     expect "uncached workspace fallback preserves full results" (small = result));
  let calls = ref 0 in
  let cancel () =
    incr calls;
    !calls > 2000
  in
  expect "cancellation while preparing/reusing boundaries"
    (P.greeks ~cancel cfg (requests [ A.Vega; A.Rho ]) admitted Side.Put
    = Error A.Cancelled)

let () =
  check false;
  check true;
  print_endline "American Greek boundary reuse controls passed"
