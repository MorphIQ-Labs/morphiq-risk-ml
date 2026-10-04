(* The mutation catalog: every numerical mechanism the docs claim, removed.

   The type system already rejects the structural mistakes (test/types). What
   it cannot see is a well-typed numerical mistake: [Split.two_sum a b] and
   [(a +. b, 0.0)] have the same type. Each mutant here removes one such
   mechanism and names the test that must fail without it.

   A mutant replaces one exact snippet (it must occur exactly once, so a
   catalog that drifts from the code fails loudly). It counts as killed only
   when it compiles (a compiler rejection proves nothing about the tests) and
   the named test fails (so the kill comes from the oracle or property that
   guards the mechanism).

   The full baseline runs once; each compiled mutant runs its named guard.
   Everything uses the [mutation] dune profile, which disables the
   determinism digest (any numerical change trips it) and leaves warnings
   non-fatal. Work happens in a temporary copy of the tracked files; the
   checkout is never modified.

     dune exec scripts/mutation/mutation.exe              run the catalog
     dune exec scripts/mutation/mutation.exe -- --core    run the CI core
     dune exec scripts/mutation/mutation.exe -- --list    print it
     dune exec scripts/mutation/mutation.exe -- ID ...    run the named mutants *)

type mutant = {
  id : string;
  file : string;
  snippet : string;
  replacement : string;
  killer : string;  (** The test that must fail. *)
  mechanism : string;
}

(* The quotient remainder has a direct coordinate oracle: near S/K = 1,
   rounding rho once loses relative accuracy even when the final price happens
   to round identically. The intrinsic branch guard remains an explicit probe,
   not a claim of universal indistinguishability (error-analysis §5.1). *)
let catalog =
  [
    {
      id = "prepared-quotient-exponent";
      file = "lib/dd.ml";
      snippet =
        "scale (mul numerator divisor.reciprocal) (exponent - divisor.exponent)";
      replacement = "scale (mul numerator divisor.reciprocal) exponent";
      killer = "prepared_division";
      mechanism = "prepared division restores the divisor exponent";
    };
    {
      id = "prepared-reciprocal-residual";
      file = "lib/dd.ml";
      snippet = "let reciprocal = add_float d th in";
      replacement = "let reciprocal = of_float th in";
      killer = "prepared_division";
      mechanism = "prepared reciprocal retains its low-word correction";
    };
    {
      id = "prepared-numerator-scale";
      file = "lib/dd.ml";
      snippet = "else snd (Float.frexp numerator.hi) - 1";
      replacement = "else 0";
      killer = "prepared_division";
      mechanism =
        "prepared division normalizes extreme dividends before the product";
    };
    {
      id = "inverse-iteration-count";
      file = "lib/normal.ml";
      snippet = "let inverse_steps = 6";
      replacement = "let inverse_steps = 2";
      killer = "oracle_normal";
      mechanism = "bounded inverse iteration reaches its accuracy requirement";
    };
    {
      id = "inverse-dd-refinement";
      file = "lib/normal.ml";
      snippet = "if x <= Normal_dd.limit then";
      replacement = "if false then";
      killer = "oracle_normal";
      mechanism =
        "double-word correction preserves sampled inverse monotonicity";
    };
    {
      id = "erfcx-leading-residual";
      file = "lib/cody.ml";
      snippet =
        "coefficients.(0)\n\
        \    +. Float.fma !tail offset Erf_coefficients.local_low.(index)";
      replacement = "Float.fma !tail offset coefficients.(0)";
      killer = "oracle_greeks";
      mechanism = "leading coefficient residual in cancelling BSM theta";
    };
    {
      id = "erfcx-local-degree";
      file = "lib/cody.ml";
      snippet = "let coefficients = Erf_coefficients.local.(index) in";
      replacement =
        "let coefficients = Array.sub Erf_coefficients.local.(index) 0 7 in";
      killer = "oracle_normal";
      mechanism = "generated local erfcx Taylor remainder";
    };
    {
      id = "erfcx-tail-degree";
      file = "lib/cody.ml";
      snippet = "horner Erf_coefficients.tail (inverse *. inverse)";
      replacement =
        "horner (Array.sub Erf_coefficients.tail 0 4) (inverse *. inverse)";
      killer = "oracle_normal";
      mechanism = "Gaussian-integral asymptotic remainder";
    };
    {
      id = "erf-series-degree";
      file = "lib/cody.ml";
      snippet = "horner Erf_coefficients.small (x *. x)";
      replacement = "horner (Array.sub Erf_coefficients.small 0 5) (x *. x)";
      killer = "oracle_normal";
      mechanism = "odd small-erf series remainder";
    };
    {
      id = "erfc-square-split";
      file = "lib/cody.ml";
      snippet = "Split.scaled_exp_neg (erfcx_nonnegative x) hi lo";
      replacement = "Split.scaled_exp_neg (erfcx_nonnegative x) hi 0.0";
      killer = "oracle_normal";
      mechanism = "erfc tail retains the exact square residual";
    };
    {
      id = "planner-snapshot-copy";
      file = "lib/planner.ml";
      snippet =
        "let market = Array.copy market and portfolio = Array.copy portfolio in";
      replacement = "let market = market and portfolio = portfolio in";
      killer = "planner_contract";
      mechanism = "caller mutations cannot change a frozen plan";
    };
    {
      id = "planner-post-expiry";
      file = "lib/planner.ml";
      snippet = "if days < 0L then Error Post_expiry";
      replacement = "if false then Error Post_expiry";
      killer = "planner_contract";
      mechanism = "post-expiry valuation has an explicit settlement exclusion";
    };
    {
      id = "planner-scalar-radius";
      file = "lib/planner.ml";
      snippet = "(number q v.absolute_error)";
      replacement = "0.0";
      killer = "planner_contract";
      mechanism = "aggregation retains each scalar certificate uncertainty";
    };
    {
      id = "planner-incomplete-total";
      file = "lib/planner.ml";
      snippet = "complete = s.failed = 0 && Option.is_some successful_subset;";
      replacement = "complete = Option.is_some successful_subset;";
      killer = "planner_contract";
      mechanism = "failed items prevent complete portfolio totals";
    };
    {
      id = "production-accuracy-limit";
      file = "lib/production.ml";
      snippet = "else if absolute_error > limit then Error Accuracy_exceeded";
      replacement = "else if false then Error Accuracy_exceeded";
      killer = "production_boundary";
      mechanism = "a computed certificate must meet the requested accuracy";
    };
    {
      id = "production-certificate-radius";
      file = "lib/production.ml";
      snippet = "let absolute_error = E.error_of_float enclosed value in";
      replacement = "let absolute_error = 0.0 in";
      killer = "production_reference";
      mechanism = "the served leading word retains its actual absolute error";
    };
    {
      id = "production-rho-coordinate";
      file = "lib/model_enclosure.ml";
      snippet = "if rho_forward then forward_rho ()";
      replacement = "if true then forward_rho ()";
      killer = "production_greek_reference";
      mechanism = "BSM rho holds yield fixed even when its value equals rate";
    };
    {
      id = "production-time-unit";
      file = "lib/model_enclosure.ml";
      snippet = "let daily v = E.div_float v Units.days_per_year in";
      replacement = "let daily v = v in";
      killer = "production_greek_reference";
      mechanism = "runtime Greek certificates retain per-calendar-day units";
    };
    {
      id = "zero-variance-black-time";
      file = "lib/black.ml";
      snippet =
        "theta = (if smooth_time then Greeks.daily 0.0 else Greeks.kink);";
      replacement = "theta = Greeks.kink;";
      killer = "boundary_greeks";
      mechanism = "a spot payoff kink does not erase a smooth time derivative";
    };
    {
      id = "zero-variance-normal-rho";
      file = "lib/bachelier.ml";
      snippet = "rho = Ok 0.0;";
      replacement = "rho = Greeks.kink;";
      killer = "boundary_greeks";
      mechanism = "ATM zero-variance forward rho exists and is zero";
    };
    {
      id = "zero-variance-veta";
      file = "lib/boundary_greeks.ml";
      snippet = "rounded (E.div_float annual Units.days_per_year)";
      replacement = "let _ = annual in Ok 0.0";
      killer = "boundary_greeks";
      mechanism = "the maturity derivative of right vega is generally nonzero";
    };
    {
      id = "enclosure-product-guard";
      file = "lib/enclosure.ml";
      snippet = "abs a >= 0x1p-485 && abs b >= 0x1p-485";
      replacement = "abs a >= 0x1p-600 && abs b >= 0x1p-600";
      killer = "enclosure_reference";
      mechanism =
        "the product shortcut must imply a representable residual quantum";
    };
    {
      id = "iv-certification-refinement";
      file = "lib/adaptive_iv.ml";
      snippet = "Full.run inputs side ~quote ~proposal";
      replacement = "Certified_iv.Numerical_failure";
      killer = "oracle_iv";
      mechanism =
        "an inconclusive first certificate must retain full-evaluator \
         availability";
    };
    {
      id = "enclosure-series-tail";
      file = "lib/enclosure.ml";
      snippet = "let result = ref (add_error !sum tail) in";
      replacement = "let result = ref (let _ = tail in !sum) in";
      killer = "enclosure_reference";
      mechanism =
        "the cheaper exponential cannot discard its analytical truncation \
         remainder";
    };
    {
      id = "certified-rounding-cell";
      file = "lib/certified_iv.ml";
      snippet = "if rounding_cell proposal then Root proposal";
      replacement = "if true then Root proposal";
      killer = "certified_iv_reference";
      mechanism = "a proposal cannot bypass exact-model rounding acceptance";
    };
    {
      id = "enclosure-discarded-word";
      file = "lib/enclosure.ml";
      snippet = "else take 0 kept (error +^ abs x) rest";
      replacement = "else take 0 kept error rest";
      killer = "enclosure_reference";
      mechanism = "discarded expansion words remain in the absolute radius";
    };
    {
      id = "iv-original-shift";
      file = "lib/black.ml";
      snippet = "original_spot_low = spot_low;";
      replacement = "original_spot_low = 0.0;";
      killer = "iv_termination";
      mechanism = "classification retains original sparse shifted input words";
    };
    {
      id = "model-normalization";
      file = "lib/model_enclosure.ml";
      snippet = "let inv_sqrt_2pi = E.div one (E.sqrt (E.mul_float pi 2.0))";
      replacement = "let inv_sqrt_2pi = E.exact 0.3989422804014327";
      killer = "enclosure_reference";
      mechanism = "normalization constant requires an enclosure of its low bits";
    };
    {
      id = "enclosure-fma-underflow";
      file = "lib/enclosure.ml";
      snippet = "let error = if ea + eb >= -968 then 0.0 else quantum in";
      replacement = "let error = if ea + eb >= -968 then 0.0 else 0.0 in";
      killer = "enclosure_reference";
      mechanism =
        "a fused product residual can underflow and is not always exact";
    };
    {
      id = "iv-iteration-cap";
      file = "lib/iv_iteration.ml";
      snippet = "else if n >= max_iterations then Error Non_convergence";
      replacement = "else if n >= max_iterations then Ok candidate";
      killer = "iv_termination";
      mechanism = "iteration exhaustion cannot manufacture a root";
    };
    {
      id = "iv-nonfinite-value";
      file = "lib/iv_iteration.ml";
      snippet =
        "let v = value candidate in\n\
        \          if not (Float.is_finite v) then Error Numerical_failure";
      replacement =
        "let v = value candidate in\n\
        \          if not (Float.is_finite v) then Ok candidate";
      killer = "iv_termination";
      mechanism = "nonfinite evaluator output is an arithmetic failure";
    };
    {
      id = "split-root-nonoverlap";
      file = "lib/split.ml";
      snippet = "let hi, lo = (sum, lo -. (sum -. hi)) in";
      replacement = "let hi, lo = (hi, lo) in";
      killer = "dd_reference";
      mechanism = "normalize the square-root correction before DD consumers";
    };
    {
      id = "dd-scale-nonoverlap";
      file = "lib/dd.ml";
      snippet =
        "if lo <> 0.0 && Float.abs lo < Float.min_float && Float.is_finite hi \
         then";
      replacement = "if false then";
      killer = "dd_reference";
      mechanism = "restore DD nonoverlap after subnormal low-word scaling";
    };
    {
      id = "scaled-exp-prefactor";
      file = "lib/split.ml";
      snippet = "(1077.0 +. float (ceiling_exponent + k)) *. ln2_hi";
      replacement = "(1100.0 +. float k) *. ln2_hi";
      killer = "numerical_regressions";
      mechanism = "a large prefactor rescues a representable exponential tail";
    };
    {
      id = "split-root-scale";
      file = "lib/split.ml";
      snippet = "else (snd (Float.frexp t) - 1) asr 1";
      replacement = "else 0";
      killer = "dd_reference";
      mechanism = "retain the square-root residual for extreme maturities";
    };
    {
      id = "split-quotient-scale";
      file = "lib/split.ml";
      snippet =
        "let en = snd (Float.frexp n) - 1 and ed = snd (Float.frexp d) - 1 in";
      replacement = "let en = 0 and ed = 0 in";
      killer = "dd_reference";
      mechanism =
        "normalize the compensated quotient before taking its residual";
    };
    {
      id = "split-quotient-nonoverlap";
      file = "lib/split.ml";
      snippet = "(hi, r -. (hi -. q))";
      replacement = "(q, r)";
      killer = "dd_reference";
      mechanism =
        "normalize the two quotient words before DD consumers use them";
    };
    {
      id = "reference-expansion";
      file = "test/bounds.ml";
      snippet =
        "Float.abs (List.fold_left ( +. ) 0.0 (List.fold_left grow [] terms))";
      replacement = "let _ = grow in Float.abs (List.fold_left (+.) 0.0 terms)";
      killer = "numerical_regressions";
      mechanism =
        "reference discrepancy retains cancellation between high and low words";
    };
    {
      id = "sqrt-exponent-scale";
      file = "lib/dd.ml";
      snippet = "else (snd (Float.frexp a.hi) - 1) asr 1";
      replacement = "else 0";
      killer = "dd_reference";
      mechanism = "even-exponent normalization before the square-root residual";
    };
    {
      id = "intrinsic-coordinate-scale";
      file = "lib/black.ml";
      snippet =
        "if x.hi <> 0.0 && Float.abs x.hi < 0x1p-500 && x_terms <= 1.0 then";
      replacement = "if false then";
      killer = "numerical_regressions";
      mechanism =
        "retain a tiny displaced spread before restoring the currency scale";
    };
    {
      id = "rho-ulp-propagation";
      file = "test/bounds.ml";
      snippet =
        "(Float.abs time *. price_error) +. (0.5 *. ulp got) +. (0.5 *. ulp \
         reference)";
      replacement =
        "let _ = time, price_error, got in (budget +. 1.0) *. ulp reference";
      killer = "numerical_regressions";
      mechanism = "price ULP counts do not survive multiplication by T";
    };
    {
      id = "quotient-remainder";
      file = "lib/black.ml";
      snippet =
        "Dd.add (Dd.log_float q) (Dd.sub rho (Dd.mul_float (Dd.mul rho rho) \
         0.5))";
      replacement =
        "let rho = Dd.of_float (Dd.to_float rho) in\n\
        \      Dd.add (Dd.log_float q) (Dd.sub rho (Dd.mul_float (Dd.mul rho \
         rho) 0.5))";
      killer = "numerical_regressions";
      mechanism = "double-word quotient remainder near unit spot/strike ratios";
    };
    {
      id = "division-numerator-scale";
      file = "lib/dd.ml";
      snippet = "else snd (Float.frexp a.hi) - 1";
      replacement = "else 0";
      killer = "dd_reference";
      mechanism = "normalise the dividend before the reciprocal product";
    };
    {
      id = "expm1-tiny";
      file = "lib/dd.ml";
      snippet = "if Float.abs r.hi < 0x1p-104 then r";
      replacement = "if Float.abs r.hi < 0x1p-104 then of_float 0.0";
      killer = "dd_reference";
      mechanism = "retain the nonzero tiny expm1 result";
    };
    {
      id = "intrinsic-tiny-carry";
      file = "lib/black.ml";
      snippet = "c.spot = c.strike && c.spot_low = c.strike_low";
      replacement = "false && c.spot = c.strike && c.spot_low = c.strike_low";
      killer = "numerical_regressions";
      mechanism = "carry below the exponent range, restored at currency scale";
    };
    {
      id = "dd-reference-nan";
      file = "test/dd_reference.ml";
      snippet = "let e = error got exponent (f h) (f l) (f tail) in";
      replacement =
        "let _ = got in let e = error (Dd.of_float Float.nan) exponent (f h) \
         (f l) (f tail) in";
      killer = "dd_reference";
      mechanism = "nonfinite component outputs must fail the DD scorer";
    };
    {
      id = "floor-exponent";
      file = "lib/black.ml";
      snippet = "(snd (Float.frexp spot) + snd (Float.frexp strike)) asr 1";
      replacement = "(snd (Float.frexp spot) + snd (Float.frexp strike)) / 2";
      killer = "properties";
      mechanism = "floor-divided scale exponent (exact homogeneity)";
    };
    {
      id = "intrinsic-expm1";
      file = "lib/black.ml";
      snippet =
        "if Float.abs c.x <= 0.35 && c.x_terms <= 1.0 then Dd.mul cash \
         (Dd.expm1 x)";
      replacement = "if false then Dd.mul cash (Dd.expm1 x)";
      killer = "oracle_price";
      mechanism = "near-the-money intrinsic as C expm1(x)";
    };
    {
      id = "root-time-low";
      file = "lib/black.ml";
      snippet = "root_time_low = snd (Split.sqrt time);";
      replacement = "root_time_low = 0.0;";
      killer = "oracle_price";
      mechanism = "sqrt T, and so s = sigma sqrt T, in double-double";
    };
    {
      id = "subnormal-rounding";
      file = "lib/dd.ml";
      snippet =
        "if Float.abs v >= Float.min_float || a.hi = 0.0 || not \
         (Float.is_finite v)";
      replacement = "if true";
      killer = "test_morphiq_risk";
      mechanism = "one rounding into the subnormals (Dd.to_float_scaled)";
    };
    {
      id = "displaced-exact-sum";
      file = "lib/black.ml";
      snippet =
        "let f, fl = Split.two_sum i.forward i.displacement\n\
        \          and k, kl = Split.two_sum i.strike i.displacement in";
      replacement =
        "let f, fl = (i.forward +. i.displacement, 0.0)\n\
        \          and k, kl = (i.strike +. i.displacement, 0.0) in";
      killer = "oracle_price";
      mechanism = "displaced Black on the exact sums F + d, K + d";
    };
    {
      id = "bachelier-distance";
      file = "lib/bachelier.ml";
      snippet = "Split.two_sum i.forward (-.i.strike)";
      replacement = "(i.forward -. i.strike, 0.0)";
      killer = "oracle_price";
      mechanism = "Bachelier F - K with its remainder";
    };
    {
      id = "gaussian-split";
      file = "lib/normal.ml";
      snippet = "Split.scaled_exp_neg scale (0.5 *. hi) (0.5 *. lo)";
      replacement = "Split.scaled_exp_neg scale (0.5 *. hi) 0.0";
      killer = "oracle_normal";
      mechanism = "exact split of u^2 in exp(-u^2/2)";
    };
    {
      id = "log1p-remainder";
      file = "lib/elementary.ml";
      snippet = "let d, dl = two_sum 2.0 f in";
      replacement = "let d, dl = (2.0 +. f, 0.0) in";
      killer = "oracle_elementary";
      mechanism = "log1p's quotient remainder";
    };
    {
      id = "dd-exp-degree";
      file = "lib/dd.ml";
      snippet =
        "let acc = ref exp_coefficients.(21) in\n    for k = 20 downto 2 do";
      replacement =
        "let acc = ref exp_coefficients.(11) in\n    for k = 10 downto 2 do";
      killer = "dd_reference";
      mechanism = "degree-22 Taylor remainder in the double-word exponential";
    };
    {
      id = "normal-dd-series";
      file = "lib/normal_dd.ml";
      snippet = "Float.abs term.Dd.hi <= 0x1p-110 *. Float.abs acc.Dd.hi";
      replacement = "Float.abs term.Dd.hi <= 0x1p-60 *. Float.abs acc.Dd.hi";
      killer = "normal_dd_reference";
      mechanism = "Marsaglia's series to double-double precision";
    };
    {
      id = "iv-complement-correction";
      file = "lib/black.ml";
      snippet = "else if beta > 0.5 *. b_max then";
      replacement = "else if false then";
      killer = "numerical_regressions";
      mechanism = "the final Newton step on the complement near the maximum";
    };
    {
      id = "greeks-theta-dd";
      file = "lib/black.ml";
      snippet =
        "if\n\
        \        Float.abs d1_dd.Dd.hi <= Normal_dd.limit\n\
        \        && Float.abs d2_dd.Dd.hi <= Normal_dd.limit\n\
        \      then";
      replacement = "if false then";
      killer = "oracle_greeks";
      mechanism = "Black theta in double-double near the money";
    };
    {
      id = "greeks-charm-dd";
      file = "lib/black.ml";
      snippet = "if Float.abs d1_dd.Dd.hi <= Normal_dd.limit then charm_dd ()";
      replacement = "if false then charm_dd ()";
      killer = "oracle_greeks";
      mechanism = "Black charm's bracket in double-double";
    };
    {
      id = "greeks-veta-bracket";
      file = "lib/black.ml";
      snippet =
        "(Dd.sub (Dd.mul q_plus_d1_w rt_dd) (Dd.div (Dd.of_float 0.5) rt_dd))";
      replacement =
        "(Dd.of_float ((Dd.to_float q_plus_d1_w *. rt) -. (0.5 /. rt)))";
      killer = "oracle_greeks";
      mechanism = "veta's sqrt(T)-scaled bracket in double-double";
    };
    {
      id = "bachelier-theta-dd";
      file = "lib/bachelier.ml";
      snippet =
        "if Float.abs dh <= Normal_dd.limit then\n\
        \            let d_dd = { Dd.hi = dh; lo = dl } in";
      replacement =
        "if false then\n            let d_dd = { Dd.hi = dh; lo = dl } in";
      killer = "oracle_greeks";
      mechanism = "Bachelier theta in double-double near the money";
    };
  ]

(* Keep the required PR workload small. This is a sentinel set, not exhaustive
   coverage: shared DD preconditions, independent scoring, exponent rescue,
   inverse conditioning and cancellation in both model families. The complete
   catalog remains a separate manual/scheduled assurance run. *)
let core_ids =
  [
    "split-root-nonoverlap";
    "dd-scale-nonoverlap";
    "reference-expansion";
    "scaled-exp-prefactor";
    "certified-rounding-cell";
    "greeks-theta-dd";
    "bachelier-theta-dd";
  ]

let core_catalog () =
  List.map
    (fun id ->
      match List.filter (fun m -> m.id = id) catalog with
      | [ m ] -> m
      | _ -> failwith ("core mutant missing or ambiguous: " ^ id))
    core_ids

(* Diagnostic only: a survivor is recorded, never called impossible to kill.
   Run with --probe intrinsic-terms; exit 1 means a compiled survivor. *)
let probes =
  [
    {
      id = "iv-maximum-error";
      file = "test/iv_bounds.ml";
      snippet = "u +. (e_max /. gap_lower)";
      replacement = "u +. (0.0 /. gap_lower)";
      killer = "numerical_regressions";
      mechanism = "maximum-leg error amplified by the complement gap";
    };
    {
      id = "bachelier-iv-quantum";
      file = "test/iv_bounds.ml";
      snippet = "+. 0x1p-1074 in";
      replacement = "+. 0.0 in";
      killer = "oracle_iv";
      mechanism = "absolute rounding error for subnormal Bachelier quotes";
    };
    {
      id = "iv-rounded-bound";
      file = "lib/black.ml";
      snippet = "if p = intrinsic.hi then root 0.0 else Iv.Below_intrinsic";
      replacement = "if false then root 0.0 else Iv.Below_intrinsic";
      killer = "oracle_iv";
      mechanism = "a quote equal to the rounded intrinsic is sigma = 0 (#448)";
    };
    {
      id = "iv-beta-bar";
      file = "lib/black.ml";
      snippet = "Dd.to_float (Dd.div (Dd.sub maximum (Dd.of_float p)) m_dd)";
      replacement = "Elementary.exp (0.5 *. x) -. beta";
      killer = "oracle_iv";
      mechanism = "beta-bar from the exact distance to the maximum";
    };
    {
      id = "iv-ln-beta";
      file = "lib/black.ml";
      snippet =
        "(if intrinsic.hi > 0.0 then Elementary.log (Dd.to_float otm)\n\
        \         else Elementary.log price -. (float c.exponent *. \
         Split.ln2_hi))\n\
        \        -. Elementary.log m";
      replacement = "Elementary.log beta";
      killer = "oracle_iv";
      mechanism = "ln beta from the unscaled quote";
    };
    {
      id = "intrinsic-terms";
      file = "lib/black.ml";
      snippet =
        "if Float.abs c.x <= 0.35 && c.x_terms <= 1.0 then Dd.mul cash \
         (Dd.expm1 x)";
      replacement = "if Float.abs c.x <= 0.35 then Dd.mul cash (Dd.expm1 x)";
      killer = "oracle_price";
      mechanism =
        "intrinsic branch guard; current end-to-end corpus may not distinguish \
         it";
    };
  ]

(* Process plumbing. *)

(* A dune started from [dune exec] inherits variables that tell it it is
   nested; the child builds an independent tree, so they are dropped. *)
let child_env () =
  Unix.environment () |> Array.to_list
  |> List.filter (fun v ->
         not
           (String.starts_with ~prefix:"INSIDE_DUNE=" v
           || String.starts_with ~prefix:"DUNE_" v))
  |> Array.of_list

(* Runs [prog args] in [cwd]; returns the exit code and combined output. *)
let run ~cwd prog args =
  let log = Filename.temp_file "mutation" ".log" in
  let fd = Unix.openfile log [ O_WRONLY; O_TRUNC ] 0o600 in
  let previous = Sys.getcwd () in
  Sys.chdir cwd;
  let pid =
    Unix.create_process_env prog
      (Array.of_list (prog :: args))
      (child_env ()) Unix.stdin fd fd
  in
  Sys.chdir previous;
  Unix.close fd;
  let _, status = Unix.waitpid [] pid in
  let output = In_channel.with_open_bin log In_channel.input_all in
  Sys.remove log;
  let code =
    match status with WEXITED c -> c | WSIGNALED _ | WSTOPPED _ -> 255
  in
  (code, output)

let dune ~cwd args =
  run ~cwd "dune" (args @ [ "--root"; "."; "--profile"; "mutation" ])

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then (
    mkdir_p (Filename.dirname dir);
    Sys.mkdir dir 0o755)

let read path = In_channel.with_open_bin path In_channel.input_all

let write path text =
  Out_channel.with_open_bin path (fun oc -> output_string oc text)

(* The tracked files, copied into a fresh directory. *)
let copy_tree root =
  let code, listing = run ~cwd:root "git" [ "ls-files" ] in
  if code <> 0 then failwith "git ls-files failed";
  let dest = Filename.temp_dir "mutation" "" in
  String.split_on_char '\n' listing
  |> List.iter (fun name ->
         if name <> "" then (
           let target = Filename.concat dest name in
           mkdir_p (Filename.dirname target);
           write target (read (Filename.concat root name))));
  dest

(* Occurrences of [needle] in [hay]. *)
let count needle hay =
  let n = String.length needle and m = String.length hay in
  let rec go i acc =
    if i > m - n then acc
    else if String.sub hay i n = needle then go (i + n) (acc + 1)
    else go (i + 1) acc
  in
  if n = 0 then 0 else go 0 0

let replace needle by hay =
  let n = String.length needle in
  let rec find i = if String.sub hay i n = needle then i else find (i + 1) in
  let i = find 0 in
  String.sub hay 0 i ^ by ^ String.sub hay (i + n) (String.length hay - i - n)

(* Mirror each designated test's ordinary action, including both price files.
   Missing mappings or fixtures fail before any mutant is scored. Native
   executables avoid an ambient bytecode DLL search-path dependency. *)
let guard_arguments = function
  | "oracle_price" -> [ [ "european" ]; [ "displaced" ] ]
  | "oracle_iv" | "certified_iv_reference" -> [ [ "iv" ] ]
  | "enclosure_reference" | "dd_reference" -> [ [ "dd" ] ]
  | "oracle_normal" -> [ [ "normal" ] ]
  | "oracle_elementary" -> [ [ "elementary" ] ]
  | "oracle_greeks" -> [ [ "greeks" ] ]
  | "boundary_greeks" -> [ [ "boundary_greeks" ] ]
  | "production_reference" -> [ [ "greek_bits"; "model_enclosures" ] ]
  | "production_greek_reference" -> [ [ "greek_bits" ] ]
  | "production_boundary" | "planner_contract" | "prepared_division" -> [ [] ]
  | "numerical_regressions" -> [ [ "regressions" ] ]
  | "iv_termination" | "normal_dd_reference" | "properties"
  | "test_morphiq_risk" ->
      [ [] ]
  | name -> failwith ("no explicit mutation guard action for " ^ name)

type guard_result = Passed | Rejected of string | Invalid of string

let guard ~cwd name =
  let executable = "_build/default/test/" ^ name ^ ".exe" in
  let actions =
    List.map
      (List.map (fun fixture ->
           "_build/default/oracle/fixtures/" ^ fixture ^ ".txt"))
      (guard_arguments name)
  in
  if
    not
      (List.for_all
         (fun file -> Sys.file_exists (Filename.concat cwd file))
         (executable :: List.concat actions))
  then Invalid ("missing executable/fixture for " ^ name)
  else
    let results = List.map (run ~cwd executable) actions in
    if
      List.exists (fun (code, _) -> code <> 0 && code <> 1 && code <> 2) results
    then Invalid ("guard did not finish normally: " ^ name)
    else
      match List.find_opt (fun (code, _) -> code <> 0) results with
      | None -> Passed
      | Some (_, output) -> Rejected output

(* Symbolic links (dune's _build/.../latest) are removed, not followed. *)
let rec remove_tree path =
  if (Unix.lstat path).st_kind = Unix.S_DIR then (
    Array.iter
      (fun f -> remove_tree (Filename.concat path f))
      (Sys.readdir path);
    Sys.rmdir path)
  else Sys.remove path

let guard_controls () =
  let work = Filename.temp_dir "mutation-guard-controls" "" in
  Fun.protect
    ~finally:(fun () -> remove_tree work)
    (fun () ->
      let dir = Filename.concat work "_build/default/test" in
      mkdir_p dir;
      let script name body =
        let path = Filename.concat dir (name ^ ".exe") in
        write path ("#!/bin/sh\n" ^ body ^ "\n");
        Unix.chmod path 0o700
      in
      let check message ok = if not ok then failwith message in
      check "missing guard was accepted"
        (match guard ~cwd:work "iv_termination" with
        | Invalid _ -> true
        | _ -> false);
      script "iv_termination" "exit 0";
      check "passing guard was rejected"
        (guard ~cwd:work "iv_termination" = Passed);
      List.iter
        (fun code ->
          script "iv_termination" ("exit " ^ string_of_int code);
          check "completed rejecting guard was not recorded"
            (match guard ~cwd:work "iv_termination" with
            | Rejected _ -> true
            | _ -> false))
        [ 1; 2 ];
      script "iv_termination" "kill -TERM $$";
      check "signalled guard was called a kill"
        (match guard ~cwd:work "iv_termination" with
        | Invalid _ -> true
        | _ -> false);
      script "oracle_iv" "exit 1";
      check "missing fixture was called a kill"
        (match guard ~cwd:work "oracle_iv" with
        | Invalid _ -> true
        | _ -> false);
      print_endline "mutation guard controls pass")

let score work m =
  let path = Filename.concat work m.file in
  let source = read path in
  match count m.snippet source with
  | 1 ->
      write path (replace m.snippet m.replacement source);
      Fun.protect
        ~finally:(fun () -> write path source)
        (fun () ->
          match dune ~cwd:work [ "build" ] with
          | c, _ when c <> 0 ->
              Error (Printf.sprintf "INVALID   %s: does not compile" m.id)
          | _ -> (
              match guard ~cwd:work m.killer with
              | Passed ->
                  Error (Printf.sprintf "SURVIVED  %s: %s" m.id m.mechanism)
              | Invalid why ->
                  Error (Printf.sprintf "INVALID   %s: %s" m.id why)
              | Rejected _ ->
                  Ok (Printf.sprintf "killed    %s by %s" m.id m.killer)))
  | n ->
      Error
        (Printf.sprintf "STALE     %s: snippet occurs %d times in %s" m.id n
           m.file)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  if args = [ "--self-test" ] then (
    guard_controls ();
    exit 0);
  let args, catalog =
    match args with
    | "--probe" :: rest -> (rest, probes)
    | "--core" :: rest -> (rest, core_catalog ())
    | _ -> (args, catalog)
  in
  if args = [ "--list" ] then
    List.iter
      (fun m ->
        Printf.printf "%-26s %-20s %-20s %s\n" m.id m.file m.killer m.mechanism)
      catalog
  else
    let unknown =
      List.filter (fun a -> not (List.exists (fun m -> m.id = a) catalog)) args
    in
    if unknown <> [] then (
      prerr_endline ("unknown mutants: " ^ String.concat ", " unknown);
      exit 2);
    let selected =
      if args = [] then catalog
      else List.filter (fun m -> List.mem m.id args) catalog
    in
    (* dune exec runs from the workspace root. *)
    let work = copy_tree (Sys.getcwd ()) in
    let status =
      Fun.protect
        ~finally:(fun () -> remove_tree work)
        (fun () ->
          let start = Unix.gettimeofday () in
          match dune ~cwd:work [ "test" ] with
          | c, output when c <> 0 ->
              print_endline
                "baseline fails under the mutation profile; fix it before \
                 scoring mutants";
              print_string output;
              1
          | _ ->
              Printf.printf "baseline passes (%.0f s)\n%!"
                (Unix.gettimeofday () -. start);
              (* Establish that the direct actions start and pass with the
                 very same arguments before attributing a failure to mutation. *)
              List.map (fun m -> m.killer) selected
              |> List.sort_uniq compare
              |> List.iter (fun name ->
                     match guard ~cwd:work name with
                     | Passed -> ()
                     | Rejected output ->
                         failwith
                           ("direct baseline guard failed: " ^ name ^ "\n"
                          ^ output)
                     | Invalid why -> failwith why);
              let bad =
                List.fold_left
                  (fun bad m ->
                    match score work m with
                    | Ok line ->
                        print_endline line;
                        flush stdout;
                        bad
                    | Error line ->
                        print_endline line;
                        flush stdout;
                        bad + 1)
                  0 selected
              in
              Printf.printf "%d of %d mutants killed as catalogued\n"
                (List.length selected - bad)
                (List.length selected);
              if bad = 0 then 0 else 1)
    in
    exit status
