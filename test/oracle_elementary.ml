(* Scores the deterministic elementary functions against correctly rounded
   mpmath references (oracle/gen_elementary.py). Each reference carries its
   residual (exact - reference), so errors are measured in fractions of an
   ULP.

   - log1p on its reduced path, f in [sqrt(1/2) - 1, sqrt 2 - 1] with
     |f| >= 2^-54: the derived bound |z - y| <= ulp(z)/2 + 0.085 u |y|
     (docs/error-analysis.md §1).
   - Everything else: within 1 ULP of the correctly rounded value. *)

open Morphiq_risk.Internal

let ordered x =
  let b = Int64.bits_of_float x in
  if Int64.compare b 0L < 0 then Int64.neg (Int64.logand b Int64.max_int) else b

let ulps a b =
  if Float.is_nan a && Float.is_nan b then 0.0
  else if Float.is_nan a || Float.is_nan b then Float.infinity
  else Int64.to_float (Int64.abs (Int64.sub (ordered a) (ordered b)))

let eval = function
  | "exp" -> Elementary.exp
  | "expm1" -> Elementary.expm1
  | "log" -> Elementary.log
  | "log1p" -> Elementary.log1p
  | f -> invalid_arg f

(* The reduced path, where the derivation applies: |x| >= 2^-54 (below it
   log1p returns x, exactly rounded). *)
let direct_log1p x =
  Float.abs x >= 0x1p-54
  && x >= 0x1.6a09e667f3bcdp-1 -. 1.0
  && x <= 0x1.6a09e667f3bcdp0 -. 1.0

type stat = {
  mutable n : int;
  mutable worst : float;  (** Integer ULP distance to the reference. *)
  mutable at : float;
  mutable worst_fraction : float;  (** |error| / ulp, against the exact value. *)
}

let () =
  let stats = Hashtbl.create 4 and failures = ref [] in
  let reduced_worst = ref 0.0 in
  let fail s = if List.length !failures < 20 then failures := s :: !failures in
  let ic = open_in Sys.argv.(1) in
  (try
     while true do
       let line = input_line ic in
       if line <> "" && line.[0] <> '#' then
         Scanf.sscanf line "%s %Lx %Lx %Lx" (fun fn xb rb eb ->
             let x = Int64.float_of_bits xb
             and r = Int64.float_of_bits rb
             and residual = Int64.float_of_bits eb in
             let got = eval fn x in
             let u = ulps got r in
             let st =
               match Hashtbl.find_opt stats fn with
               | Some st -> st
               | None ->
                   let st =
                     { n = 0; worst = 0.0; at = 0.0; worst_fraction = 0.0 }
                   in
                   Hashtbl.add stats fn st;
                   st
             in
             st.n <- st.n + 1;
             if u > st.worst then (
               st.worst <- u;
               st.at <- x);
             (* got - r is exact for neighbours (Sterbenz); the residual
                then places the exact value. *)
             let error =
               if Float.is_finite r && Float.is_finite got then
                 Float.abs (got -. r -. residual)
               else 0.0
             in
             let unit = Bounds.ulp r in
             if Float.is_finite r && r <> 0.0 then
               st.worst_fraction <- Float.max st.worst_fraction (error /. unit);
             if fn = "log1p" && direct_log1p x then (
               let exact = r +. residual in
               let bound =
                 (0.5 *. Bounds.ulp got)
                 +. (0.085 *. Bounds.u *. Float.abs exact)
               in
               reduced_worst :=
                 Float.max !reduced_worst (error /. Bounds.ulp got);
               if not (error <= bound) then
                 fail
                   (Printf.sprintf
                      "log1p(%h) = %h: %.4f ULP from exact, bound %.4f" x got
                      (error /. unit) (bound /. unit)))
             else if u > 1.0 then
               fail
                 (Printf.sprintf "%s(%h) = %h, reference %h (%.0f ulp)" fn x got
                    r u))
     done
   with End_of_file -> close_in ic);
  Hashtbl.iter
    (fun fn st ->
      Printf.printf
        "%-6s %7d rows, worst %.0f ulp at %h, worst %.4f ulp from exact\n" fn
        st.n st.worst st.at st.worst_fraction)
    stats;
  Printf.printf
    "log1p reduced path: worst %.4f ulp from exact (bound 0.5 + 0.085)\n"
    !reduced_worst;
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
