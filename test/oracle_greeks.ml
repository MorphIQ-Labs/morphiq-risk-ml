(* Scores the ten Greeks against independently generated model references.
   Every finite expected value also needs an analytical certificate, including
   below-binary64 rows. Historical ULP targets are additional quality gates;
   they are not premises of that certificate. Kinks require refusal.
   Optional FerroRisk cross-check statuses are handled explicitly below. *)

open Morphiq_risk

let f = Int64.float_of_bits

let ordered x =
  let b = Int64.bits_of_float x in
  if Int64.compare b 0L < 0 then Int64.neg (Int64.logand b Int64.max_int) else b

let ulps a b =
  if Float.is_nan a || Float.is_nan b then Float.infinity
  else Int64.to_float (Int64.abs (Int64.sub (ordered a) (ordered b)))

open Greek_values

let budget = Hashtbl.create 32

let () =
  List.iter (fun (k, v) -> Hashtbl.replace budget k v) Budget_greeks.values

type stat = {
  mutable n : int;
  mutable fails : int;
  mutable worst : float;
  mutable errors : float list;
  mutable worst_line : string;
}

let certificate model ~side ~s ~k ~t ~r ~q ~sigma ~shift greek =
  if t = 0.0 || sigma = 0.0 then
    Certified.boundary model ~side ~s ~k ~t ~r ~q ~sigma ~shift greek
  else if model = "bachelier" then
    List.assoc greek (Certified.bachelier ~side ~s ~k ~t ~r ~sigma ())
  else Certified.black model ~side ~s ~k ~t ~r ~q ~sigma ~shift greek

let () =
  let stats = Hashtbl.create 64 and other = Hashtbl.create 16 in
  let certified = ref 0 and certificate_domains = Hashtbl.create 8 in
  let failures = ref [] in
  let ic = open_in Sys.argv.(1) in
  let show_worst = Array.length Sys.argv > 2 in
  (try
     while true do
       let line = input_line ic in
       if line <> "" && line.[0] <> '#' then
         Scanf.sscanf line "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
           (fun model side greek status s k t r q sigma shift reference ->
             let s = f s
             and k = f k
             and t = f t
             and r = f r
             and q = f q
             and sigma = f sigma
             and shift = f shift
             and reference = f reference in
             let side = if side = "call" then Side.Call else Side.Put in
             let got =
               match greeks model side ~s ~k ~t ~r ~q ~sigma ~shift with
               | `Black g -> pick g greek
               | `Normal g -> pick g greek
               | exception Failure _ -> Ok Float.nan
             in
             let family =
               if model = "bachelier" then "bachelier" else "black"
             in
             let fail what =
               if List.length !failures < 25 then
                 failures :=
                   Printf.sprintf "%s %s %s: %s | %s" model greek status what
                     line
                   :: !failures
             in
             let note k =
               Hashtbl.replace other k
                 (1 + Option.value ~default:0 (Hashtbl.find_opt other k))
             in
             match status with
             | ("resolved" | "single_route") when not (Float.is_nan reference)
               -> (
                 let key = family ^ " " ^ greek in
                 let st =
                   match Hashtbl.find_opt stats key with
                   | Some st -> st
                   | None ->
                       let st =
                         {
                           n = 0;
                           fails = 0;
                           worst = 0.0;
                           errors = [];
                           worst_line = "";
                         }
                       in
                       Hashtbl.add stats key st;
                       st
                 in
                 st.n <- st.n + 1;
                 match got with
                 | Ok v ->
                     (try
                        let b =
                          certificate model ~side ~s ~k ~t ~r ~q ~sigma ~shift
                            greek
                        in
                        if not (Certified.replay_matches v b) then (
                          st.fails <- st.fails + 1;
                          fail
                            (Printf.sprintf
                               "certificate replay %h differs from served %h"
                               b.v v))
                        else if not (Certified.check ~got:v ~reference b) then (
                          st.fails <- st.fails + 1;
                          fail
                            (Printf.sprintf "derived error %.4g exceeds %.4g"
                               (Float.abs (v -. reference))
                               b.e))
                        else incr certified
                      with Certified.Unsupported why ->
                        st.fails <- st.fails + 1;
                        fail ("derived certificate unavailable: " ^ why);
                        Hashtbl.replace certificate_domains why
                          (1
                          + Option.value ~default:0
                              (Hashtbl.find_opt certificate_domains why)));
                     let u = ulps v reference in
                     st.errors <- u :: st.errors;
                     if u > st.worst then (
                       st.worst <- u;
                       st.worst_line <- line);
                     (* Forward models, live: rho = -T V exactly, so it must
                        be RN(-T V) of the served price, and its error is the
                        price's absolute error multiplied by T, plus rounding.
                        ULP spacings must be converted before composition. At expiry rho is the contract's limit. *)
                     let composed_ok, b =
                       if forward_rho model greek && t > 0.0 then
                         let p = price model side ~s ~k ~t ~r ~sigma ~shift in
                         ( Int64.equal (Int64.bits_of_float v)
                             (Int64.bits_of_float (-.t *. p)),
                           Bounds.scaled_price_error ~time:t ~price:p ~got:v
                             ~reference
                             ~budget:(Bounds.price_ulp_budget_max family)
                           /. Bounds.ulp reference )
                       else
                         ( true,
                           Option.value ~default:Float.infinity
                             (Hashtbl.find_opt budget key) )
                     in
                     if not composed_ok then (
                       st.fails <- st.fails + 1;
                       fail (Printf.sprintf "rho %h is not RN(-T V)" v));
                     if
                       not
                         (Bounds.within
                            ~error:(Float.abs (v -. reference))
                            ~bound:(b *. Bounds.ulp reference))
                     then (
                       st.fails <- st.fails + 1;
                       fail
                         (Printf.sprintf
                            "got %h, reference %h (%.0f ulp > %.0f)" v reference
                            u b))
                 | Error _ ->
                     st.fails <- st.fails + 1;
                     fail "refused a resolved derivative")
             | "below_binary64" -> (
                 match got with
                 | Ok v when Float.abs v <= 4.0 *. 0x1p-1074 -> (
                     note "below_binary64 -> ~0";
                     try
                       let b =
                         certificate model ~side ~s ~k ~t ~r ~q ~sigma ~shift
                           greek
                       in
                       if Certified.check ~got:v ~reference:0.0 b then
                         incr certified
                       else fail "derived subnormal Greek bound exceeded"
                     with Certified.Unsupported why ->
                       fail ("derived subnormal certificate unavailable: " ^ why)
                     )
                 | Ok v ->
                     note "below_binary64 -> nonzero";
                     fail (Printf.sprintf "got %h, expected ~0" v)
                 | Error _ ->
                     note "below_binary64 -> refused";
                     fail "refused")
             | "above_binary64" -> (
                 match got with
                 | Ok v
                   when Float.is_integer v = false
                        && Float.abs v = Float.infinity ->
                     note "above_binary64 -> inf"
                 | Error _ -> note "above_binary64 -> refused"
                 | Ok v ->
                     note "above_binary64 -> finite";
                     fail (Printf.sprintf "got %h, expected overflow" v))
             | "kink" -> (
                 match got with
                 | Error Greeks.Payoff_kink -> note "kink -> refused"
                 | Ok v ->
                     note "kink -> value";
                     fail (Printf.sprintf "got %h, expected a kink refusal" v))
             | _ ->
                 note
                   (status
                   ^
                   match got with
                   | Ok _ -> " -> value"
                   | Error _ -> " -> refused"))
     done
   with End_of_file -> close_in ic);
  let median l =
    let a = Array.of_list l in
    Array.sort compare a;
    if Array.length a = 0 then 0.0 else a.(Array.length a / 2)
  in
  Printf.printf "Derived Greek certificates: %d rows\n" !certified;
  Hashtbl.iter
    (fun why n -> Printf.printf "outside certificate domain: %s: %d\n" why n)
    certificate_domains;
  if !certified = 0 then failwith "no derived Greek coverage";
  Printf.printf "%-18s %6s %12s %8s %8s %6s\n" "family greek" "rows" "worst ulp"
    "median" "budget" "fails";
  Hashtbl.fold (fun k _ acc -> k :: acc) stats []
  |> List.sort compare
  |> List.iter (fun key ->
         let st = Hashtbl.find stats key in
         Printf.printf "%-18s %6d %12.4g %8.2g %8s %6d\n" key st.n st.worst
           (median st.errors)
           (match Hashtbl.find_opt budget key with
           | Some b -> Printf.sprintf "%.0f" b
           | None -> "-")
           st.fails;
         if show_worst then Printf.printf "   worst: %s\n" st.worst_line);
  Printf.printf "other statuses:\n";
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) other []
  |> List.sort compare
  |> List.iter (fun (k, v) -> Printf.printf "  %-36s %d\n" k v);
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
