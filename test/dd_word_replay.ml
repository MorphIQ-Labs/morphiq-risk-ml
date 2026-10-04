(* Manual compatibility trace of production functions, without the test-only
   checked-DD wrappers. Independent error scoring remains in dd_reference. *)
open Morphiq_risk.Internal

let () =
  if Array.length Sys.argv <> 2 then invalid_arg "dd_word_replay FIXTURE";
  Oracle_fixture.lines ~columns:[ 9 ] ~names:[ "dd" ] Sys.argv.(1)
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line "%s %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
             (fun fn ah al bh bl _exponent _h _l _tail ->
               let f = Int64.float_of_bits in
               let a = Dd.{ hi = f ah; lo = f al }
               and b = Dd.{ hi = f bh; lo = f bl } in
               let got =
                 match fn with
                 | "exp" -> Dd.exp a
                 | "expm1" -> Dd.expm1 a
                 | "log" -> Dd.log_float a.hi
                 | "sqrt" -> Dd.sqrt a
                 | "div" -> Dd.div a b
                 | "split_sqrt" ->
                     let hi, lo = Split.sqrt a.hi in
                     Dd.{ hi; lo }
                 | "split_quotient" ->
                     let hi, lo = Split.quotient_dd a.hi a.lo b.hi b.lo in
                     Dd.{ hi; lo }
                 | "normal_pdf" -> Normal_dd.pdf a
                 | "normal_cdf" -> Normal_dd.cdf a
                 | "erfcx" -> Dd.of_float (Cody.erfcx_nonnegative a.hi)
                 | "y_prime" -> Dd.of_float (Normalised_black.y_prime a.hi)
                 | "black_kernel" ->
                     Dd.of_float
                       (Normalised_black.scaled 1.0 a.hi a.lo b.hi b.lo)
                 | _ -> invalid_arg fn
               in
               Printf.printf "%s\t%016Lx %016Lx\n" line
                 (Int64.bits_of_float got.hi)
                 (Int64.bits_of_float got.lo)))
