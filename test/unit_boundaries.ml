open Morphiq_risk
module First = Black.Make (Black.Bsm_carry)
module Second = Black.Make (Black.Bsm_carry)

(* Reusing an identical carry path is applicative, not a fresh model token. *)
let _same_carry (a : First.admitted) : Second.admitted = a
let require label condition = if not condition then failwith label

let () =
  let rejected constructor x =
    match constructor x with
    | Error (Refusal.Invalid_input { parameter = Refusal.Volatility; _ }) ->
        true
    | _ -> false
  in
  List.iter
    (fun x ->
      require "lognormal constructor admits invalid volatility"
        (rejected Vol.lognormal x);
      require "normal constructor admits invalid volatility"
        (rejected Vol.normal x))
    [ -0x1p-1074; -1.0; Float.infinity; Float.neg_infinity; Float.nan ];
  let retained constructor x =
    match constructor x with
    | Ok v -> Int64.bits_of_float (Vol.to_float v) = Int64.bits_of_float x
    | Error _ -> false
  in
  List.iter
    (fun x ->
      require "lognormal coordinate round trip" (retained Vol.lognormal x);
      require "normal coordinate round trip" (retained Vol.normal x))
    [ -0.0; 0.0; 0x1p-1074; 1.0; Float.max_float ];
  let daily : (Units.per_calendar_day, Vol.normal) Units.volatility_time_rate =
    Units.volatility_time_rate 1.0
  in
  let annual : (Units.per_year, Vol.normal) Units.volatility_time_rate =
    Units.annualise_volatility daily
  in
  require "mixed annualisation scales and retains coordinate"
    ((annual :> float) = 365.0);
  (* Labels deliberately do not validate numerical provenance or finiteness. *)
  let labelled : Vol.lognormal Units.per_volatility =
    Units.per_volatility Float.nan
  in
  require "raw labels must not be represented as finite-value validators"
    (Float.is_nan (labelled :> float));
  print_endline "Volatility admission and mixed Greek unit boundaries passed"
