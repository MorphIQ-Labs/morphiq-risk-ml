(* Let's Be Rational round trip s -> b(x, s) -> s over a grid in (x, s),
   held to 8x Jäckel's attainable relative accuracy (1 + |b / (s b')|) eps. *)
open Morphiq_risk

let () =
  let worst = ref 0.0 and worst_at = ref (0.0, 0.0) and n = ref 0 and fails = ref 0 in
  List.iter
    (fun x ->
      List.iter
        (fun s ->
          let beta = Internal.Normalised_black.b x s in
          if beta > 0.0 && beta < Float.exp (0.5 *. x) && beta > 1e-300 then begin
            incr n;
            let s' = Internal.Lbr.solve beta x in
            (* Attainable relative accuracy in s: (1 + |b / (s b')|) eps. *)
            let attainable = (1.0 +. Float.abs (beta /. (s *. Internal.Normalised_black.vega x s))) *. epsilon_float in
            let err = Float.abs (s' -. s) /. s /. attainable in
            if Float.is_nan err || err > 8.0 then incr fails;
            if Float.is_nan err || err > !worst then (worst := err; worst_at := (x, s))
          end)
        [ 1e-4; 1e-3; 0.01; 0.05; 0.1; 0.2; 0.5; 1.0; 2.0; 3.0; 5.0; 10.0; 20.0; 40.0 ])
    [ 0.0; -1e-12; -1e-6; -1e-3; -0.01; -0.1; -0.5; -1.0; -2.0; -5.0; -10.0; -30.0; -100.0; -250.0; -600.0 ];
  Printf.printf "cases %d, worst %.2f x attainable at x=%g s=%g, over 8x: %d\n" !n !worst (fst !worst_at)
    (snd !worst_at) !fails;
  if !fails > 0 then exit 1
