(* Enforced ULP budgets per family and Greek: twice the measured worst,
   rounded up to a power of two (docs/results-greeks.md). *)
let values =
  [
    ("black delta", 16.0);
    ("black gamma", 8.0);
    ("black theta", 64.0);
    ("black vega", 8.0);
    ("black rho", 16.0);
    ("black vanna", 8.0);
    ("black volga", 8.0);
    ("black charm", 8.0);
    ("black veta", 8.0);
    ("black color", 16.0);
    ("bachelier delta", 8.0);
    ("bachelier gamma", 4.0);
    ("bachelier theta", 32.0);
    ("bachelier vega", 4.0);
    ("bachelier rho", 8.0);
    ("bachelier vanna", 4.0);
    ("bachelier volga", 8.0);
    ("bachelier charm", 8.0);
    ("bachelier veta", 4.0);
    ("bachelier color", 8.0);
  ]
