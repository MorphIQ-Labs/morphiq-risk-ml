(* Exact-input value/refusal checks; a finite baseline is never its own oracle. *)
open Morphiq_risk

let record_only = Sys.getenv_opt "MORPHIQ_FINITE_GREEKS_RECORD_ONLY" = Some "1"
let require message yes = if not yes then failwith message

let get = function
  | Ok x -> x
  | Error _ -> failwith "unexpected admission refusal"

let ulps = Float_score.ulps
let count = ref 0
let refused = ref 0
let checked = ref 0
let kinks = ref 0

let () =
  require "ULP scorer must reject opposite-sign overflow witness"
    (ulps 2. (-2.) = 0x1p63);
  require "ULP scorer rejects NaN" (ulps Float.nan 0. = Float.infinity);
  require "ULP scorer keeps one-word spacing" (ulps 1. (Float.succ 1.) = 1.);
  require "ULP scorer identifies signed zeros" (ulps 0. (-0.) = 0.);
  Oracle_fixture.lines ~columns:[ 13 ] ~names:[ "finite_greeks" ] Sys.argv.(1)
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line "%s %s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
             (fun
               model side name field status s k t r q sigma shift reference ->
               let f = Int64.float_of_bits in
               let side_value = if side = "call" then Side.Call else Side.Put in
               let value =
                 match
                   Greek_values.greeks model side_value ~s:(f s) ~k:(f k)
                     ~t:(f t) ~r:(f r) ~q:(f q) ~sigma:(f sigma)
                     ~shift:(f shift)
                 with
                 | `Black g -> Greek_values.pick g field
                 | `Normal g -> Greek_values.pick g field
               in
               (if record_only then
                  let shown =
                    match value with
                    | Ok v -> Printf.sprintf "ok:%016Lx" (Int64.bits_of_float v)
                    | Error Greeks.Payoff_kink -> "kink"
                    | Error Greeks.Numerical_failure -> "numerical_failure"
                  in
                  Printf.printf "%s %s %s %s %s\n" model side name field shown);
               incr count;
               if not record_only then
                 let context = model ^ " " ^ side ^ " " ^ name ^ " " ^ field in
                 match (status, value) with
                 | "kink", Error Greeks.Payoff_kink -> incr kinks
                 | "kink", _ -> failwith (context ^ ": coordinate kink lost")
                 | ( ("resolved" | "above_binary64"),
                     Error Greeks.Numerical_failure ) ->
                     incr refused
                 | "resolved", Ok v ->
                     let family =
                       if model = "bachelier" then model else "black"
                     in
                     let budget =
                       List.assoc (family ^ " " ^ field) Budget_greeks.values
                     in
                     let error = ulps v (f reference) in
                     require
                       (Printf.sprintf "%s: %h vs %h, %.0f ULP > %.0f" context v
                          (f reference) error budget)
                       (error <= budget);
                     (* Zero references also need exact zero; a small ULP budget is
                 not permission to turn a proved underflow into a positive value. *)
                     if f reference = 0. then
                       require (context ^ ": nonzero at zero reference") (v = 0.);
                     incr checked
                 | _ ->
                     failwith
                       (context ^ ": invalid success/failure classification")));
  let certificate_or_failure label = function
    | Error Production.Numerical_failure | Error Production.Accuracy_exceeded ->
        ()
    | Ok certificate ->
        (* Independent gamma < 2^-1076 proof in finite-greek-results.md.
           A positive binary64 radius around zero therefore covers it. *)
        require
          (label ^ ": unsound production certificate")
          (certificate.Production.value = 0.
          && Float.is_finite certificate.absolute_error
          && certificate.absolute_error > 0.
          && certificate.absolute_error <= 1e-10)
    | Error _ -> failwith (label ^ ": wrong production failure class")
  in
  let normal =
    get
      (Production.Bachelier.admit
         { forward = 100.; strike = 101.; time_to_expiry = 1.; rate = 0. })
  in
  certificate_or_failure "Bachelier"
    (Production.Bachelier.evaluate normal Side.Call
       (get (Vol.normal 1e-310))
       Production.Gamma ~max_error:1e-10);
  let black =
    get
      (Production.Black76.admit
         { forward = 100.; strike = 101.; time_to_expiry = 1.; rate = 0. })
  in
  certificate_or_failure "Black76"
    (Production.Black76.evaluate black Side.Call
       (get (Vol.lognormal 1e-310))
       Production.Gamma ~max_error:1e-10);
  require "empty challenge fixture" (!count = 880);
  if not record_only then
    require "no successful independent value checks"
      (!checked > 0 && !refused > 0 && !kinks > 0);
  Printf.eprintf
    "%d outcomes: %d independently checked finite values, %d explicit \
     failures, %d kinks\n"
    !count !checked !refused !kinks
