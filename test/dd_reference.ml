(* Generated exact-input references with three words and a separate exponent.
   Both input words are exercised; errors are scored at the reference's scale.
   No library DD operation participates in the error calculation. *)
open Morphiq_risk.Internal

let error (got : Dd.t) exponent h l tail =
  if not (Float.is_finite got.hi && Float.is_finite got.lo) then Float.infinity
  else
    let gh = Float.ldexp got.hi (-exponent)
    and gl = Float.ldexp got.lo (-exponent) in
    Float.abs (gh -. h +. (gl -. l) -. tail)

let () =
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
               let got, relative =
                 match fn with
                 | "exp" -> (Dd.exp a, Bounds.eps_exp (Dd.to_float a))
                 | "expm1" -> (Dd.expm1 a, Bounds.eps_expm1 (Dd.to_float a))
                 | "log" -> (Dd.log_float a.hi, Bounds.eps_log)
                 | "sqrt" -> (Dd.sqrt a, 3.125 *. Bounds.u2)
                 | "div" -> (Dd.div a b, 9.8 *. Bounds.u2)
                 | _ -> invalid_arg fn
               in
               incr rows;
               if a.lo <> 0.0 || b.lo <> 0.0 then incr nonzero_low;
               let e = error got exponent (f h) (f l) (f tail) in
               (* At most one quantum from independently scaling two result
                  components; 2^-158 encloses the oracle expansion. The relative inflation
                  covers rounding in the scorer's three subtractions and sum. *)
               let bound =
                 (relative *. (1.0 +. (8.0 *. Bounds.u)) *. Float.abs (f h))
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
