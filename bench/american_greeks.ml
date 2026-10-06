open Morphiq_risk
module A = Early_exercise.Bsm
module P = A.Piecewise

let get = function Ok x -> x | Error _ -> failwith "benchmark setup"
let sigma x = get (Vol.lognormal x)

let constant =
  A.
    {
      spot = 100.;
      strike = 100.;
      rate = 0.05;
      dividend_yield = 0.02;
      time_to_expiry = 1.;
      opens_at = 0.;
      volatility = sigma 0.2;
    }

let piecewise cash =
  P.
    {
      spot = 100.;
      strike = 100.;
      time_to_expiry = 1.;
      opens_at = 0.;
      rate =
        get
          (Rate.create ~horizon:1. ~initial:0.05
             ~changes:
               (if cash then [| (0.5, -0.03) |]
                else [| (0.25, 0.08); (0.75, -0.03) |]));
      dividend_yield =
        get
          (Yield.create ~horizon:1. ~initial:0.02
             ~changes:(if cash then [| (0.5, 0.08) |] else [| (0.5, 0.06) |]));
      volatility =
        get
          (Volatility.create ~horizon:1. ~initial:(sigma 0.2)
             ~changes:
               (if cash then [| (0.5, sigma 0.35) |]
                else [| (0.375, sigma 0.3) |]));
    }

let requests spatial =
  let xs =
    [ (A.Delta, 0.02); (A.Gamma, 0.002); (A.Theta, 0.005) ]
    @ if spatial then [] else [ (A.Vega, 1.); (A.Rho, 1.) ]
  in
  get
    (A.configure_greeks
       (List.map
          (fun (q, tolerance) ->
            get
              (A.request_greek
                 ?bump:(if q = A.Vega || q = A.Rho then Some 0x1p-10 else None)
                 ~tolerance q))
          xs))

let configuration parts =
  let limits =
    A.
      {
        max_nodes = 8192;
        max_steps = parts * 131072;
        max_policy_solves = parts * 1048576;
        max_row_visits = parts * 1000000000;
        max_workspace_bytes = 8388608;
        policy_iterations = 64;
      }
  in
  get
    (A.configure ~tolerance:1. ~space_cells:128 ~time_steps:128
       ~domain_expansions:2 ~limits)

let run model quantity =
  let price_cfg = configuration 1
  and greek_cfg = configuration (if quantity = "spatial" then 2 else 14) in
  let requested = requests (quantity = "spatial") in
  let encode outcome =
    match outcome with
    | Error _ -> failwith "benchmark outer price failure"
    | Ok (r : A.estimated_greeks) ->
        let estimated, unavailable, rejected =
          List.fold_left
            (fun (e, u, f) (_, x) ->
              match x with
              | A.Greek_estimate _ -> (e + 1, u, f)
              | A.Greek_unavailable _ -> (e, u + 1, f)
              | A.Greek_failure _ | A.Greek_accuracy_not_demonstrated _ ->
                  (e, u, f + 1))
            (0, 0, 0) r.greeks
        in
        ( r.price.value,
          estimated,
          unavailable,
          rejected,
          Digest.to_hex (Digest.string (Marshal.to_string r [])) )
  in
  let price value =
    match value with
    | Error _ -> failwith "benchmark price failure"
    | Ok (p : A.estimated_price) ->
        ( p.value,
          0,
          0,
          0,
          Digest.to_hex (Digest.string (Marshal.to_string p [])) )
  in
  let execute =
    if model = "constant" then
      let admitted = get (A.admit constant) in
      if quantity = "price" then fun () ->
        price (A.price price_cfg admitted Side.Put)
      else fun () -> encode (A.greeks greek_cfg requested admitted Side.Put)
    else
      let cash = model = "cash" in
      let admitted =
        get
          (if cash then
             P.admit_cash (piecewise true)
               A.
                 {
                   valuation_side = Regular;
                   opening_side = Regular;
                   expiry_side = Regular;
                   dividends = [| { time = 0.5; amount = 5. } |];
                 }
           else P.admit (piecewise false))
      in
      if quantity = "price" then fun () ->
        price (P.price price_cfg admitted Side.Put)
      else fun () -> encode (P.greeks greek_cfg requested admitted Side.Put)
  in
  let warm = execute () in
  Gc.full_major ();
  let before = Gc.quick_stat ()
  and bytes = Gc.allocated_bytes ()
  and start = Unix.gettimeofday () in
  let result = execute () in
  let elapsed = Unix.gettimeofday () -. start
  and allocation = Gc.allocated_bytes () -. bytes in
  let after = Gc.stat () in
  if result <> warm then failwith "benchmark repeated outcome changed";
  let value, estimated, unavailable, rejected, digest = result in
  Printf.printf
    "{\"model\":%S,\"quantity\":%S,\"calls\":1,\"warmup_calls\":1,\"seconds_per_call\":%.17g,\"allocated_bytes_per_call\":%.17g,\"minor_collections\":%d,\"major_collections\":%d,\"heap_words_after\":%d,\"live_words_after\":%d,\"price\":%.17g,\"estimated_greeks\":%d,\"unavailable_greeks\":%d,\"rejected_greeks\":%d,\"digest\":%S}\n"
    model quantity elapsed allocation
    (after.minor_collections - before.minor_collections)
    (after.major_collections - before.major_collections)
    after.heap_words after.live_words value estimated unavailable rejected
    digest

let () =
  match Array.to_list Sys.argv with
  | ([ _; "--mode"; model; quantity ] | [ _; "--"; model; quantity ])
    when List.mem model [ "constant"; "piecewise"; "cash" ]
         && List.mem quantity [ "price"; "spatial"; "all" ] ->
      run model quantity
  | [ _; "--help" ] ->
      print_endline
        "american-greeks --mode constant|piecewise|cash price|spatial|all"
  | [ _; "--version" ] -> print_endline "american-greeks-benchmark 1"
  | _ ->
      prerr_endline "invalid benchmark arguments";
      exit 2
