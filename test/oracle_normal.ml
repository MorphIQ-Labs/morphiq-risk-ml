(* Scores the normal primitives against oracle/data/normal_reference.txt
   (oracle/gen_normal.py). Budgets are FerroRisk SPEC §5.1/§5.2, applied to
   the correctly rounded reference. *)

open Morphiq_risk

let ordered f =
  let b = Int64.bits_of_float f in
  if Int64.compare b 0L < 0 then Int64.neg (Int64.logand b Int64.max_int) else b

let ulps a b =
  if Float.is_nan a && Float.is_nan b then 0L
  else if Float.is_nan a || Float.is_nan b then Int64.max_int
  else Int64.abs (Int64.sub (ordered a) (ordered b))

let min_normal = Float.min_float

type budget = { name : string; ulps : int64 }

let budget fn x =
  match fn with
  | "pdf" -> { name = "pdf"; ulps = 4L }
  | "erfcx" -> { name = "erfcx"; ulps = 4L }
  | "erf" -> { name = "erf"; ulps = 4L }
  | "erfc" -> { name = "erfc"; ulps = 4L }
  | "logcdf" -> { name = "logcdf"; ulps = 4L }
  (* FerroRisk allows 6e-14 relative here, the cost of rounding x^2 before
     exp. The exact square split removes that term, so the tail holds the
     body's 6 ULP; a mutant that drops the split measures 484 ULP. *)
  | "cdf" when x <= -8.0 -> { name = "cdf tail (x <= -8)"; ulps = 6L }
  | "cdf" -> { name = "cdf body"; ulps = 6L }
  | "inv" when Float.abs (x -. 0.5) <= 0.425 ->
      { name = "inv central"; ulps = 4L }
  | "inv" -> { name = "inv tail"; ulps = 8L }
  | _ -> invalid_arg fn

(* Conditional composition of the enforced CDF and elementary budgets.
   Evaluate the actual inner result; bound its exact value in a neighbourhood
   whose largest spacing accounts for crossing a binade. Six ULP to RN(Phi)
   plus reference rounding gives 6.5 spacings. The mean-value denominator is
   the minimum over this entire neighbourhood, not its centre. *)
let logcdf_composed x r got =
  let erf_region = Internal.Cody.thresh /. 0.70710678118654752440 in
  let outer_rounding = (2.0 *. Bounds.ulp got) +. (0.5 *. Bounds.ulp r) in
  let compose p denominator =
    let spacing = Bounds.ulp (Float.abs p +. (7.0 *. Bounds.ulp p)) in
    let e = 6.5 *. spacing in
    let lower = denominator -. e in
    if lower <= 0.0 then Some Float.infinity
    else Some ((e /. lower) +. outer_rounding)
  in
  if x > erf_region then
    let q = Normal.norm_cdf (-.x) in
    compose q (1.0 -. q)
  else if x >= -.erf_region then
    let phi = Normal.norm_cdf x in
    compose phi phi
  else None

let eval = function
  | "pdf" -> Normal.norm_pdf
  | "cdf" -> Normal.norm_cdf
  | "logcdf" -> Normal.log_norm_cdf
  | "erfcx" -> Internal.Cody.erfcx
  | "erf" -> Internal.Cody.erf
  | "erfc" -> Internal.Cody.erfc
  | "inv" -> Normal.norm_inv
  | fn -> invalid_arg fn

type stat = {
  mutable n : int;
  mutable worst : int64;
  mutable worst_x : float;
  mutable fails : int;
  mutable worst_rel : float;
}

let () =
  let path = Sys.argv.(1) in
  if not (Sys.file_exists path) then (
    Printf.eprintf "ERROR: %s missing; run oracle/gen_normal.py\n" path;
    exit 2);
  let trace = Option.map open_out (Sys.getenv_opt "MORPHIQ_ORACLE_TRACE") in
  let stats = Hashtbl.create 8 in
  let failures = ref [] in
  let ic = open_in path in
  (try
     while true do
       let line = input_line ic in
       if String.length line > 0 && line.[0] <> '#' then
         Scanf.sscanf line "%s %Lx %Lx" (fun fn xb rb ->
             let x = Int64.float_of_bits xb and r = Int64.float_of_bits rb in
             let got = eval fn x in
             Option.iter
               (fun oc ->
                 Printf.fprintf oc "%s\t%016Lx\n" line (Int64.bits_of_float got))
               trace;
             let b = budget fn x in
             let d = ulps got r in
             let rel =
               if r = 0.0 then Float.abs got else Float.abs ((got -. r) /. r)
             in
             let endpoint =
               (fn = "cdf" && (r = 0.0 || r = 1.0))
               || (fn = "logcdf" && r = 0.0)
               || (fn = "erfc" && (r = 0.0 || r = 2.0))
               || (fn = "erf" && Float.abs r = 1.0)
             in
             let ok =
               (* SPEC bit contract: where the truth rounds to an endpoint,
                  the endpoint is returned exactly. *)
               if not (Float.is_finite r) then
                 Int64.equal (Int64.bits_of_float got) (Int64.bits_of_float r)
               else if not (Float.is_finite got) then false
               else if endpoint then
                 Int64.equal (Int64.bits_of_float got) (Int64.bits_of_float r)
               else
                 match
                   if fn = "logcdf" then logcdf_composed x r got else None
                 with
                 | Some bound ->
                     Bounds.within ~error:(Float.abs (got -. r)) ~bound
                 | None -> d <= b.ulps
             in
             let s =
               match Hashtbl.find_opt stats b.name with
               | Some s -> s
               | None ->
                   let s =
                     {
                       n = 0;
                       worst = 0L;
                       worst_x = 0.0;
                       fails = 0;
                       worst_rel = 0.0;
                     }
                   in
                   Hashtbl.add stats b.name s;
                   s
             in
             s.n <- s.n + 1;
             if Int64.compare d s.worst > 0 then (
               s.worst <- d;
               s.worst_x <- x);
             if r <> 0.0 && Float.abs r >= min_normal && rel > s.worst_rel then
               s.worst_rel <- rel;
             if not ok then (
               s.fails <- s.fails + 1;
               if List.length !failures < 20 then
                 failures :=
                   Printf.sprintf "%s(%h) = %h, reference %h (%Ld ulp)" fn x got
                     r d
                   :: !failures))
     done
   with End_of_file -> close_in ic);
  let names =
    Hashtbl.fold (fun k _ acc -> k :: acc) stats [] |> List.sort compare
  in
  Printf.printf "%-20s %7s %10s %12s %24s %6s\n" "quantity" "rows" "worst ulp"
    "worst rel" "at" "fails";
  List.iter
    (fun k ->
      let s = Hashtbl.find stats k in
      Printf.printf "%-20s %7d %10Ld %12.3e %24h %6d\n" k s.n s.worst
        s.worst_rel s.worst_x s.fails)
    names;
  List.iter print_endline (List.rev !failures);
  Option.iter close_out trace;
  if !failures <> [] then exit 1
