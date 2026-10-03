(* Scores exact-input prices. ULP budgets are measured regression limits.
   Both the ULP and normwise limits must hold. For Bachelier the norm includes
   sigma sqrt(T)/sqrt(2 pi): unlike Black, its price is not bounded by the
   discounted legs. See docs/error-analysis.md; no small-ULP bypass exists. *)

open Morphiq_risk

let ordered f =
  let b = Int64.bits_of_float f in
  if Int64.compare b 0L < 0 then Int64.neg (Int64.logand b Int64.max_int) else b

let ulps a b =
  if Float.is_nan a || Float.is_nan b then Float.infinity
  else Int64.to_float (Int64.abs (Int64.sub (ordered a) (ordered b)))

(* FerroRisk SPEC §7.1 (#440): (worst ULP, worst EPSILON * scale). *)
let ferro_budget family region =
  match (family, region) with
  | "black", "deep_itm" -> (175.0, 28.4)
  | "black", "itm" -> (37.0, 17.3)
  | "black", "near_atm_tiny_variance" -> (552.0, 0.10)
  | "black", "otm" -> (3504.0, 17.9)
  | "black", "extreme_scale" -> (7.3e6, 613.0)
  | "black", "zero_variance" -> (4.3e15, 567.0)
  | "bachelier", _ -> (329.0, 4.3)
  | _ -> invalid_arg region

let side_of = function
  | "call" -> Side.Call
  | "put" -> Side.Put
  | s -> invalid_arg s

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)

let price model side ~s ~k ~t ~r ~q ~sigma ~shift =
  let lognormal = get (Vol.lognormal sigma) in
  match model with
  | "bsm" ->
      let a =
        get
          (Black.Bsm.admit
             {
               spot = s;
               strike = k;
               time_to_expiry = t;
               rate = r;
               dividend_yield = q;
             })
      in
      Black.Bsm.price a side lognormal
  | "black76" ->
      let a =
        get
          (Black.Black76.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      Black.Black76.price a side lognormal
  | "displaced" ->
      (* The contract: Black-76 on the exact sums F + d and K + d
         (oracle/gen_displaced.py). *)
      let a =
        get
          (Black.Displaced.admit
             {
               forward = s;
               strike = k;
               displacement = shift;
               time_to_expiry = t;
               rate = r;
             })
      in
      Black.Displaced.price a side lognormal
  | "black76_shifted" ->
      (* FerroRisk #440's displaced rows: Black-76 on fl(F + d) and fl(K + d). *)
      let a =
        get
          (Black.Black76.admit
             {
               forward = s +. shift;
               strike = k +. shift;
               time_to_expiry = t;
               rate = r;
             })
      in
      Black.Black76.price a side lognormal
  | "bachelier" ->
      let a =
        get
          (Bachelier.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      Bachelier.price a side (get (Vol.normal sigma))
  | m -> invalid_arg m

(* EPSILON * scale, the normwise unit FerroRisk reports alongside ULP. *)
let scale model ~s ~k ~t ~r ~q ~sigma ~shift =
  let dr = Float.exp (-.r *. t) in
  match model with
  | "bsm" -> Float.max (s *. Float.exp (-.q *. t)) (k *. dr)
  | "black76" -> dr *. Float.max s k
  | "displaced" | "black76_shifted" -> dr *. Float.max (s +. shift) (k +. shift)
  | _ ->
      dr
      *. (Float.max (Float.abs s) (Float.abs k)
         +. (sigma *. Float.sqrt t /. Float.sqrt (2.0 *. Float.pi)))

type stat = {
  mutable n : int;
  mutable worst_ulp : float;
  mutable worst_scale : float;
  mutable fails : int;
  mutable errors : float list;
  mutable worst_row : string;
}

let source = ref "-"

(* The largest share of the analytical error budget E used by a zero-variance row. *)
let derived_worst = ref 0.0
let families : (string, int * int) Hashtbl.t = Hashtbl.create 4

let () =
  Printexc.record_backtrace true;
  let path = Sys.argv.(1) in
  let stats = Hashtbl.create 16 in
  let certificates = ref 0 and domains = Hashtbl.create 8 in
  let failures = ref [] in
  let ic = open_in path in
  (try
     while true do
       let line = input_line ic in
       if line <> "" && line.[0] <> '#' then
         (* This project's oracles carry a family column (grid, cancel,
            random); FerroRisk's #440 rows do not. *)
         let line =
           match String.split_on_char ' ' line with
           | [ _; _; _; _; _; _; _; _; _; _; _; _ ] as fields -> (
               match fields with
               | m :: sd :: rg :: fam :: rest ->
                   source := fam;
                   String.concat " " (m :: sd :: rg :: rest)
               | _ -> line)
           | _ ->
               source := "-";
               line
         in
         Scanf.sscanf line "%s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
           (fun model side region s k t r q sigma shift reference ->
             let f = Int64.float_of_bits in
             let s = f s
             and k = f k
             and t = f t
             and r = f r
             and q = f q
             and sigma = f sigma
             and shift = f shift
             and reference = f reference in
             let family =
               if model = "bachelier" then "bachelier" else "black"
             in
             let got =
               try price model (side_of side) ~s ~k ~t ~r ~q ~sigma ~shift
               with Failure _ -> Float.nan
             in
             Bounds.trace_float line got;
             let derived =
               if family = "black" && region = "zero_variance" then
                 Some
                   ((0.5 *. (Bounds.ulp got +. Bounds.ulp reference))
                   +. Bounds.intrinsic_error model ~s ~k ~t ~r ~q ~shift
                        ~reference)
               else None
             in
             let u = ulps got reference in
             let sc =
               Float.abs (got -. reference)
               /. (epsilon_float *. scale model ~s ~k ~t ~r ~q ~sigma ~shift)
             in
             let sc = if Float.is_nan sc then Float.infinity else sc in
             let _, scale_budget = ferro_budget family region in
             let ulp_budget = Bounds.price_ulp_budget family region in
             let key = family ^ " " ^ region in
             let st =
               match Hashtbl.find_opt stats key with
               | Some st -> st
               | None ->
                   let st =
                     {
                       n = 0;
                       worst_ulp = 0.0;
                       worst_scale = 0.0;
                       fails = 0;
                       errors = [];
                       worst_row = "";
                     }
                   in
                   Hashtbl.add stats key st;
                   st
             in
             st.n <- st.n + 1;
             (try
                let side = side_of side in
                let b =
                  if t = 0.0 || sigma = 0.0 then
                    Certified.boundary model ~side ~s ~k ~t ~r ~q ~sigma ~shift
                      "price"
                  else if model = "bachelier" then
                    List.assoc "price"
                      (Certified.bachelier ~only_price:true ~side ~s ~k ~t ~r
                         ~sigma ())
                  else
                    Certified.black model ~side ~s ~k ~t ~r ~q ~sigma ~shift
                      "price"
                in
                if
                  (not (Certified.replay_matches got b))
                  || not (Certified.check ~got ~reference b)
                then (
                  st.fails <- st.fails + 1;
                  if List.length !failures < 25 then
                    failures :=
                      Printf.sprintf
                        "derived price certificate: served %h replay %h ref %h \
                         radius %.4g | %s"
                        got b.v reference b.e line
                      :: !failures)
                else incr certificates
              with Certified.Unsupported why ->
                st.fails <- st.fails + 1;
                if List.length !failures < 25 then
                  failures :=
                    ("derived certificate unavailable: " ^ why ^ " | " ^ line)
                    :: !failures;
                let n =
                  Option.value ~default:0 (Hashtbl.find_opt domains why)
                in
                if Array.length Sys.argv > 2 && n < 3 then
                  Printf.printf "domain %s | %s\n" why line;
                if Array.length Sys.argv > 2 && n = 0 then
                  Printf.printf "%s\n" (Printexc.get_backtrace ());
                Hashtbl.replace domains why (1 + n));
             let fn, ff =
               Option.value ~default:(0, 0) (Hashtbl.find_opt families !source)
             in
             Hashtbl.replace families !source
               ( fn + 1,
                 ff
                 +
                 match derived with
                 | Some bound ->
                     if
                       Bounds.within
                         ~error:(Float.abs (got -. reference))
                         ~bound
                     then 0
                     else 1
                 | None -> if u > ulp_budget || sc > scale_budget then 1 else 0
               );
             st.errors <- u :: st.errors;
             if u > st.worst_ulp then (
               st.worst_ulp <- u;
               st.worst_row <- line);
             if sc > st.worst_scale then st.worst_scale <- sc;
             (match derived with
             | Some bound ->
                 (* The excess over the two half-ULP roundings, as a fraction
                    of E: how much of the intrinsic's analytical error the
                    served value uses. *)
                 let rounding =
                   0.5 *. (Bounds.ulp got +. Bounds.ulp reference)
                 in
                 let e = bound -. rounding in
                 if e > 0.0 then
                   derived_worst :=
                     Float.max !derived_worst
                       ((Float.abs (got -. reference) -. rounding) /. e)
             | None -> ());
             let failed =
               match derived with
               | Some bound ->
                   not
                     (Bounds.within
                        ~error:(Float.abs (got -. reference))
                        ~bound)
               | None -> u > ulp_budget || sc > scale_budget
             in
             if failed then (
               st.fails <- st.fails + 1;
               if List.length !failures < 25 then
                 failures :=
                   Printf.sprintf
                     "%s %s %s: got %h ref %h (%.0f ulp, %.2f eps*scale) | %s"
                     model side region got reference u sc line
                   :: !failures))
     done
   with End_of_file -> close_in ic);
  let median l =
    let a = Array.of_list l in
    Array.sort compare a;
    a.(Array.length a / 2)
  in
  Printf.printf "Derived price certificates: %d rows\n" !certificates;
  Hashtbl.iter
    (fun why n ->
      Printf.printf "outside price certificate domain: %s: %d\n" why n)
    domains;
  if !certificates = 0 then failwith "no derived price coverage";
  Printf.printf "%-34s %6s %10s %7s %8s %10s | %10s %8s | %5s\n" "region" "rows"
    "worst ulp" "budget" "median" "eps*scale" "ferro ulp" "ferro sc" "fails";
  Hashtbl.fold (fun k _ acc -> k :: acc) stats []
  |> List.sort compare
  |> List.iter (fun key ->
         let st = Hashtbl.find stats key in
         let family = List.hd (String.split_on_char ' ' key) in
         let region = List.nth (String.split_on_char ' ' key) 1 in
         let fu, fs = ferro_budget family region in
         Printf.printf
           "%-34s %6d %10.4g %7.0f %8.2g %10.3g | %10.3g %8.3g | %5d\n" key st.n
           st.worst_ulp
           (Bounds.price_ulp_budget family region)
           (median st.errors) st.worst_scale fu fs st.fails);
  if Hashtbl.length families > 1 || not (Hashtbl.mem families "-") then
    Hashtbl.iter
      (fun fam (n, f) ->
        Printf.printf "family %-8s rows %6d fails %d\n" fam n f)
      families;
  if Array.length Sys.argv > 2 then
    Hashtbl.iter
      (fun k st -> Printf.printf "worst %s: %s\n" k st.worst_row)
      stats;
  if Sys.argv.(1) <> "" then
    Printf.printf
      "zero variance: worst excess over rounding %.3g of the analytical error \
       budget E\n"
      !derived_worst;
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
