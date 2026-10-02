(* Scores the deterministic elementary functions against correctly rounded
   mpmath references (oracle/gen_elementary.py). Budget: 1 ULP. *)

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

let () =
  let stats = Hashtbl.create 4 and failures = ref [] in
  let ic = open_in Sys.argv.(1) in
  (try
     while true do
       let line = input_line ic in
       if line <> "" && line.[0] <> '#' then
         Scanf.sscanf line "%s %Lx %Lx" (fun fn xb rb ->
             let x = Int64.float_of_bits xb and r = Int64.float_of_bits rb in
             let got = eval fn x in
             let u = ulps got r in
             let n, worst, at =
               Option.value ~default:(0, 0.0, 0.0) (Hashtbl.find_opt stats fn)
             in
             Hashtbl.replace stats fn
               (n + 1, Float.max worst u, if u > worst then x else at);
             if u > 1.0 && List.length !failures < 20 then
               failures :=
                 Printf.sprintf "%s(%h) = %h, reference %h (%.0f ulp)" fn x got
                   r u
                 :: !failures)
     done
   with End_of_file -> close_in ic);
  Hashtbl.iter
    (fun fn (n, worst, at) ->
      Printf.printf "%-6s %7d rows, worst %.0f ulp at %h\n" fn n worst at)
    stats;
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
