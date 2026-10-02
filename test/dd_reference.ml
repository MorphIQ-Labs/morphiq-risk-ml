(* Generated exact-input references with three words and a separate exponent.
   Both input words are exercised; errors are scored at the reference's scale.
   No library DD operation participates in the error calculation. *)
open Morphiq_risk.Internal
module Dd = Certified.Dd
module Normal_dd = Certified.Normal_dd

let error (got : Dd.t) exponent h l tail =
  if not (Float.is_finite got.hi && Float.is_finite got.lo) then Float.infinity
  else
    let gh = Float.ldexp got.hi (-exponent)
    and gl = Float.ldexp got.lo (-exponent) in
    Bounds.expansion_error [ gh; -.h; gl; -.l; -.tail ]

let () =
  (* The positive-moment remainder requires a nonnegative tail coordinate.
     An uncertainty interval crossing zero cannot certify that premise. *)
  (match
     Certified.black_kernel (Certified.c 1.0)
       (Certified.D.input (-0x1p-100) 0.0 0x1p-99)
       (Certified.D.of_float 1.0)
   with
  | _ -> failwith "accepted an unresolved kernel sign"
  | exception Certified.Unsupported _ -> ());
  let rows = ref 0 and nonzero_low = ref 0 and failures = ref 0 in
  let worst = Hashtbl.create 5 in
  In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line "%s %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
             (fun fn ah al bh bl exponent h l tail ->
               let f = Int64.float_of_bits in
               let a = { Dd.hi = f ah; lo = f al }
               and b = { Dd.hi = f bh; lo = f bl } in
               let got, relative, absolute =
                 match fn with
                 | "exp" -> (Dd.exp a, Bounds.eps_exp (Dd.to_float a), 0.0)
                 | "expm1" -> (Dd.expm1 a, Bounds.eps_expm1 (Dd.to_float a), 0.0)
                 | "log" -> (Dd.log_float a.hi, Bounds.eps_log, 0.0)
                 | "sqrt" -> (Dd.sqrt a, 3.125 *. Bounds.u2, 0.0)
                 | "div" -> (Dd.div a b, 9.8 *. Bounds.u2, 0.0)
                 | "split_sqrt" ->
                     let hi, lo = Split.sqrt a.hi in
                     ({ Dd.hi; lo }, 3.125 *. Bounds.u2, 0.0)
                 | "split_quotient" ->
                     let hi, lo = Split.quotient_dd a.hi a.lo b.hi b.lo in
                     ({ Dd.hi; lo }, 16.0 *. Bounds.u2, 0.0)
                 | "normal_pdf" ->
                     (Normal_dd.pdf a, Bounds.normal_pdf_relative, 0.0)
                 | "normal_cdf" ->
                     (Normal_dd.cdf a, 0.0, Bounds.normal_cdf_absolute)
                 | "erfcx" ->
                     ( Dd.of_float (Cody.erfcx_nonnegative a.hi),
                       Bounds.erfcx_relative,
                       0.0 )
                 | "y_prime" ->
                     ( Dd.of_float (Normalised_black.y_prime a.hi),
                       Bounds.y_prime_relative,
                       0.0 )
                 | "black_kernel" ->
                     let certificate =
                       Certified.black_kernel (Certified.c 1.0)
                         (Certified.D.input a.hi a.lo 0.0)
                         (Certified.D.input b.hi b.lo 0.0)
                     in
                     let got =
                       Normalised_black.scaled 1.0 a.hi a.lo b.hi b.lo
                     in
                     if not (Certified.replay_matches got certificate) then
                       failwith "Black kernel certificate replay mismatch";
                     (Dd.of_float got, 0.0, certificate.e)
                 | _ -> invalid_arg fn
               in
               incr rows;
               if got.hi +. got.lo <> got.hi then
                 failwith (fn ^ " result words overlap");
               if a.lo <> 0.0 || b.lo <> 0.0 then incr nonzero_low;
               let e = error got exponent (f h) (f l) (f tail) in
               (* At most one quantum from independently scaling two result
                  components; 2^-158 encloses the oracle expansion. The relative inflation
                  covers rounding in the scorer's three subtractions and sum. *)
               let bound =
                 (relative *. (1.0 +. (8.0 *. Bounds.u)) *. Float.abs (f h))
                 +. Float.ldexp absolute (-exponent)
                 +. Float.ldexp 1.0 (-1074 - exponent)
                 +. 0x1p-158
               in
               let ratio = e /. bound in
               Hashtbl.replace worst fn
                 (Float.max ratio
                    (Option.value ~default:0.0 (Hashtbl.find_opt worst fn)));
               if not (Bounds.within ~error:e ~bound) then (
                 incr failures;
                 if !failures <= 15 then
                   Printf.printf "%s(%h,%h): error %.6g > %.6g\n" fn a.hi a.lo e
                     bound)));
  if !rows = 0 || !nonzero_low = 0 then failwith "empty DD coverage";
  Hashtbl.iter
    (fun fn r -> Printf.printf "%s: worst %.6g of bound\n" fn r)
    worst;
  Printf.printf "%d DD rows (%d nonzero low words), %d failures\n" !rows
    !nonzero_low !failures;
  if !failures <> 0 then exit 1
