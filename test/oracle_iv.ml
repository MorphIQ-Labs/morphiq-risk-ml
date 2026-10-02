(* Scores implied volatility against FerroRisk's public IV reference
   (oracle/convert_public_iv.py). Expected outcome by reference status:

   - root: a volatility in the rounding cell (every σ whose exact price rounds
     to the quote), or within 4x the inverse's attainable relative accuracy
     (1 + |b/(s b')|) ε of the exact root (docs/error-analysis.md §6). How
     many rows are no further from the root than FerroRisk's own largest
     observed error (public_iv_observed_envelope.json) is reported alongside.
   - zero_volatility_limit, rounded_zero_volatility_bound: σ = 0 exactly.
   - below_exact_intrinsic: Below_intrinsic.
   - no_finite_inverse, root_outside_binary64: Above_maximum.
   - expiry_not_identifiable: Not_identifiable_at_expiry.
   - invalid_input: a refusal naming the parameter, unless the model has no
     such input (Black-76, displaced Black and Bachelier take no dividend
     yield), which counts as not representable.
   - unresolved_*: the reference decides nothing; the outcome is recorded. *)

open Morphiq_risk

let f = Int64.float_of_bits

let ordered x =
  let b = Int64.bits_of_float x in
  if Int64.compare b 0L < 0 then Int64.neg (Int64.logand b Int64.max_int) else b

let ulps a b = Int64.to_float (Int64.abs (Int64.sub (ordered a) (ordered b)))

let parameter_name = function
  | Refusal.Spot | Refusal.Forward -> "spot"
  | Refusal.Strike -> "strike"
  | Refusal.Time_to_expiry -> "time_to_expiry"
  | Refusal.Rate -> "rate"
  | Refusal.Dividend_yield -> "dividend_yield"
  | Refusal.Displacement -> "displacement"
  | Refusal.Shifted_forward -> "shifted_forward"
  | Refusal.Shifted_strike -> "shifted_strike"
  | Refusal.Volatility -> "volatility"
  | Refusal.Price -> "price"

type outcome = Root of float | Below | Above | Expiry | Smallest | Refused of string

let of_iv to_float = function
  | Iv.Root v -> Root (to_float v)
  | Iv.Below_intrinsic -> Below
  | Iv.Above_maximum -> Above
  | Iv.Not_identifiable_at_expiry -> Expiry
  | Iv.Below_smallest_volatility -> Smallest

let refused (Refusal.Invalid_input { parameter; _ }) = Refused (parameter_name parameter)

let solve model side ~s ~k ~t ~r ~q ~shift ~target =
  let lift admit implied to_float =
    match admit with
    | Error e -> refused e
    | Ok a -> ( match implied a side target with Ok iv -> of_iv to_float iv | Error e -> refused e)
  in
  match model with
  | "bsm" ->
      lift
        (Black.Bsm.admit { spot = s; strike = k; time_to_expiry = t; rate = r; dividend_yield = q })
        Black.Bsm.implied Vol.to_float
  | "black76" ->
      lift (Black.Black76.admit { forward = s; strike = k; time_to_expiry = t; rate = r }) Black.Black76.implied Vol.to_float
  | "displaced" ->
      lift
        (Black.Displaced.admit { forward = s; strike = k; displacement = shift; time_to_expiry = t; rate = r })
        Black.Displaced.implied Vol.to_float
  | "bachelier" ->
      lift (Bachelier.admit { forward = s; strike = k; time_to_expiry = t; rate = r }) Bachelier.implied Vol.to_float
  | m -> invalid_arg m

let show = function
  | Root v -> Printf.sprintf "Root %h" v
  | Below -> "Below_intrinsic"
  | Above -> "Above_maximum"
  | Expiry -> "Not_identifiable_at_expiry"
  | Smallest -> "Below_smallest_volatility"
  | Refused p -> "Refused " ^ p

type stat = {
  mutable n : int;
  mutable pass : int;
  mutable in_cell : int;
  mutable within_4 : int;
  mutable within_ferro : int;
  mutable worst_ulp : float;
}

let () =
  let stats = Hashtbl.create 32 in
  let unresolved = Hashtbl.create 8 in
  let failures = ref [] in
  let ic = open_in Sys.argv.(1) in
  (try
     while true do
       let line = input_line ic in
       if line <> "" && line.[0] <> '#' then
         Scanf.sscanf line "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
           (fun model side status param s k t r q _sigma shift target lo hi root ferro ->
             let s = f s and k = f k and t = f t and r = f r and q = f q and shift = f shift in
             let target = f target and lo = f lo and hi = f hi and root = f root and ferro = f ferro in
             let side = if side = "call" then Side.Call else Side.Put in
             let got = solve model side ~s ~k ~t ~r ~q ~shift ~target in
             let key = model ^ " " ^ status in
             let st =
               match Hashtbl.find_opt stats key with
               | Some st -> st
               | None ->
                   let st = { n = 0; pass = 0; in_cell = 0; within_4 = 0; within_ferro = 0; worst_ulp = 0.0 } in
                   Hashtbl.add stats key st;
                   st
             in
             let record ok = st.n <- st.n + 1; if ok then st.pass <- st.pass + 1 in
             let fail expected =
               if List.length !failures < 30 then
                 failures := Printf.sprintf "%s %s: expected %s, got %s | %s" model status expected (show got) line :: !failures
             in
             match status with
             | "root" -> (
                 match got with
                 | Root v ->
                     let in_cell = (Float.is_nan lo || v >= lo) && (Float.is_nan hi || v <= hi) in
                     let u = ulps v root in
                     let within_ferro = Float.abs (v -. root) <= ferro in
                     if in_cell then st.in_cell <- st.in_cell + 1;
                     if u <= 4.0 then st.within_4 <- st.within_4 + 1;
                     if within_ferro then st.within_ferro <- st.within_ferro + 1;
                     if u > st.worst_ulp then st.worst_ulp <- u;
                     (* Enforced: in the rounding cell, or within 4x the inverse's
                        attainable relative accuracy (1 + |b/(s b')|) ε (Jäckel;
                        docs/error-analysis.md §6). For Bachelier, 4 ULP. *)
                     let attainable =
                       if model = "bachelier" then 4.0 *. epsilon_float
                       else
                         let s' = s +. shift and k' = k +. shift in
                         let q' = if model = "bsm" then q else r in
                         let x = -.Float.abs (Float.log (s' /. k') +. ((r -. q') *. t)) in
                         let sd = root *. Float.sqrt t in
                         if sd > 0.0 && Float.is_finite sd then
                           let b = Internal.Normalised_black.b x sd and v = Internal.Normalised_black.vega x sd in
                           4.0 *. (1.0 +. Float.abs (b /. (sd *. v))) *. epsilon_float
                         else 4.0 *. epsilon_float
                     in
                     let ok = in_cell || Float.abs (v -. root) <= attainable *. root || u <= 2.0 in
                     record ok;
                     if not ok then fail (Printf.sprintf "Root %h in [%h, %h]" root lo hi)
                 | _ -> record false; fail (Printf.sprintf "Root %h" root))
             | "zero_volatility_limit" | "rounded_zero_volatility_bound" ->
                 let ok = got = Root 0.0 in
                 record ok;
                 if not ok then fail "Root 0"
             | "below_exact_intrinsic" ->
                 let ok = got = Below in
                 record ok;
                 if not ok then fail "Below_intrinsic"
             | "no_finite_inverse" | "root_outside_binary64" ->
                 let ok = got = Above in
                 record ok;
                 if not ok then fail "Above_maximum"
             | "expiry_not_identifiable" ->
                 let ok = got = Expiry in
                 record ok;
                 if not ok then fail "Not_identifiable_at_expiry"
             | "invalid_input" ->
                 let representable = not (param = "dividend_yield" && model <> "bsm") in
                 let ok = if representable then got = Refused param else true in
                 record ok;
                 if not ok then fail ("Refused " ^ param)
             | _ ->
                 let k = status ^ " -> " ^ (match got with Root _ -> "Root" | o -> show o) in
                 Hashtbl.replace unresolved k (1 + Option.value ~default:0 (Hashtbl.find_opt unresolved k)))
     done
   with End_of_file -> close_in ic);
  Printf.printf "%-44s %5s %5s %8s %6s %8s %10s\n" "model status" "rows" "pass" "in cell" "<=4ulp" "<=ferro" "worst ulp";
  Hashtbl.fold (fun k _ acc -> k :: acc) stats []
  |> List.sort compare
  |> List.iter (fun key ->
         let st = Hashtbl.find stats key in
         let root = String.ends_with ~suffix:"root" key in
         let show n = if root then string_of_int n else "" in
         Printf.printf "%-44s %5d %5d %8s %6s %8s %10s\n" key st.n st.pass (show st.in_cell) (show st.within_4)
           (show st.within_ferro)
           (if root then Printf.sprintf "%.0f" st.worst_ulp else ""));
  Printf.printf "unresolved reference rows (no expectation):\n";
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) unresolved []
  |> List.sort compare
  |> List.iter (fun (k, v) -> Printf.printf "  %-60s %d\n" k v);
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
