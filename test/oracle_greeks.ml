(* Scores the ten Greeks against FerroRisk's Greek derivative reference
   (oracle/convert_greeks.py). Each Greek's expected outcome follows its
   reference status:

   - resolved, single_route: the value, within the enforced ULP budget.
   - below_binary64: the exact value underflows binary64, so expect a value
     within 4 subnormal quanta of zero.
   - above_binary64: the exact value overflows, so expect infinity or a refusal.
   - kink: the derivative does not exist (payoff kink), so expect a refusal.
   - boundary: a one-sided limit the reference makes no claim about. The
     outcome is recorded.

   Budgets are the measured worst per family and Greek with headroom; see
   docs/results-greeks.md. *)

open Morphiq_risk

let f = Int64.float_of_bits

let ordered x =
  let b = Int64.bits_of_float x in
  if Int64.compare b 0L < 0 then Int64.neg (Int64.logand b Int64.max_int) else b

let ulps a b =
  if Float.is_nan a || Float.is_nan b then Float.infinity
  else Int64.to_float (Int64.abs (Int64.sub (ordered a) (ordered b)))

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)

let rate =
  Result.map (fun v -> (v : Units.per_calendar_day Units.time_rate :> float))

let per_vol r = Result.map (fun v -> (v : _ Units.per_volatility :> float)) r

let per_vol2 r =
  Result.map (fun v -> (v : _ Units.per_volatility_squared :> float)) r

let pick (g : _ Greeks.t) = function
  | "delta" -> g.delta
  | "gamma" -> g.gamma
  | "theta" -> rate g.theta
  | "vega" -> per_vol g.vega
  | "rho" -> g.rho
  | "vanna" -> per_vol g.vanna
  | "volga" -> per_vol2 g.volga
  | "charm" -> rate g.charm
  | "veta" -> rate g.veta
  | "color" -> rate g.color
  | n -> invalid_arg n

let greeks model side ~s ~k ~t ~r ~q ~sigma ~shift =
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
      `Black (Black.Bsm.greeks a side (get (Vol.lognormal sigma)))
  | "black76" ->
      let a =
        get
          (Black.Black76.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      `Black (Black.Black76.greeks a side (get (Vol.lognormal sigma)))
  | "displaced" ->
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
      `Black (Black.Displaced.greeks a side (get (Vol.lognormal sigma)))
  | "bachelier" ->
      let a =
        get
          (Bachelier.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      `Normal (Bachelier.greeks a side (get (Vol.normal sigma)))
  | m -> invalid_arg m

(* The library's price, for rho = -T V in the forward models. *)
let price model side ~s ~k ~t ~r ~sigma ~shift =
  match model with
  | "black76" ->
      let a =
        get
          (Black.Black76.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      Black.Black76.price a side (get (Vol.lognormal sigma))
  | "displaced" ->
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
      Black.Displaced.price a side (get (Vol.lognormal sigma))
  | "bachelier" ->
      let a =
        get
          (Bachelier.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      Bachelier.price a side (get (Vol.normal sigma))
  | m -> invalid_arg m

let forward_rho model greek =
  greek = "rho" && List.mem model [ "black76"; "displaced"; "bachelier" ]

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

let () =
  let stats = Hashtbl.create 64 and other = Hashtbl.create 16 in
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
                 | Ok v when Float.abs v <= 4.0 *. 0x1p-1074 ->
                     note "below_binary64 -> ~0"
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
