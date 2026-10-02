open Morphiq_risk

let bits = Int64.bits_of_float
let finite = QCheck.float_range (-40.0) 40.0

let exact_points () =
  Alcotest.(check (float 0.0)) "Phi(0) = 1/2" 0.5 (Normal.norm_cdf 0.0);
  Alcotest.(check (float 0.0)) "erfcx(0) = 1" 1.0 (Cody.erfcx 0.0);
  Alcotest.(check (float 0.0)) "Phi^-1(1/2) = 0" 0.0 (Normal.norm_inv 0.5);
  Alcotest.(check bool) "Phi^-1(0) = -inf" true (Normal.norm_inv 0.0 = Float.neg_infinity);
  Alcotest.(check bool) "Phi^-1(1) = +inf" true (Normal.norm_inv 1.0 = Float.infinity);
  Alcotest.(check bool) "Phi^-1 outside [0,1] is NaN" true (Float.is_nan (Normal.norm_inv 1.5));
  Alcotest.(check bool) "erfcx below XNEG is +inf" true (Cody.erfcx (-27.0) = Float.infinity);
  List.iter
    (fun f -> Alcotest.(check bool) "NaN propagates" true (Float.is_nan (f Float.nan)))
    [ Normal.norm_pdf; Normal.norm_cdf; Normal.log_norm_cdf; Cody.erfcx ]

(* 2^-1075 (1 + δ) sits at the midpoint of the first subnormal interval.
   ldexp of the rounded sum rounds the tie to even (0) and loses δ's sign;
   rounding once from hi + lo must not. *)
let scaled_rounding () =
  let v lo = Dd.to_float_scaled { Dd.hi = 1.0; lo } (-1075) in
  Alcotest.(check (float 0.0)) "above the tie rounds up" 0x1p-1074 (v 0x1p-60);
  Alcotest.(check (float 0.0)) "below the tie rounds down" 0.0 (v (-0x1p-60));
  Alcotest.(check (float 0.0)) "an exact tie rounds to even" 0.0 (v 0.0);
  Alcotest.(check (float 0.0)) "3/2 at the tie rounds to even" 0x1p-1073 (Dd.to_float_scaled { Dd.hi = 1.5; lo = 0.0 } (-1074));
  Alcotest.(check (float 0.0)) "normal results are unaffected" 0x1.8p-1000 (Dd.to_float_scaled { Dd.hi = 1.5; lo = 0x1p-80 } (-1000))

let pdf_symmetric =
  QCheck.Test.make ~count:20_000 ~name:"phi(x) = phi(-x) bit for bit" QCheck.float (fun x ->
      Float.is_nan x || Int64.equal (bits (Normal.norm_pdf x)) (bits (Normal.norm_pdf (-.x))))

let cdf_monotone =
  QCheck.Test.make ~count:20_000 ~name:"Phi is nondecreasing" (QCheck.pair finite finite)
    (fun (a, b) ->
      let lo, hi = if a <= b then (a, b) else (b, a) in
      Normal.norm_cdf lo <= Normal.norm_cdf hi)

let cdf_symmetry =
  QCheck.Test.make ~count:20_000 ~name:"Phi(-x) ~ 1 - Phi(x)" finite (fun x ->
      Float.abs (Normal.norm_cdf (-.x) -. (1.0 -. Normal.norm_cdf x)) <= 2.0 *. epsilon_float)

let inverse_round_trip =
  QCheck.Test.make ~count:20_000 ~name:"Phi^-1(Phi(x)) ~ x on [-8, 8]" (QCheck.float_range (-8.0) 8.0)
    (fun x ->
      let p = Normal.norm_cdf x in
      (* The round trip composes both SPEC budgets: Phi's 6 ULP in p moves the
         root by 6 eps p / phi(x), and Phi^-1 adds its own 8 ULP in x. *)
      let tolerance =
        (6.0 *. epsilon_float *. p /. Normal.norm_pdf x)
        +. (8.0 *. epsilon_float *. Float.abs x)
        +. Float.min_float
      in
      Float.abs (Normal.norm_inv p -. x) <= tolerance)

let () =
  Alcotest.run "morphiq_risk"
    [
      ("normal: exact points", [ Alcotest.test_case "values" `Quick exact_points ]);
      ("dd: scaled rounding", [ Alcotest.test_case "single rounding into the subnormals" `Quick scaled_rounding ]);
      ( "normal: properties",
        List.map QCheck_alcotest.to_alcotest
          [ pdf_symmetric; cdf_monotone; cdf_symmetry; inverse_round_trip ] );
    ]
