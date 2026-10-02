(* Scores implied volatility against FerroRisk's public IV reference
   (oracle/convert_public_iv.py). Expected outcome by reference status:

   - root: for the Black family, within the derived bound of the exact root
     (black_root_bound, docs/error-analysis.md §6); for Bachelier, a
     volatility in the rounding cell (every σ whose exact price rounds to the
     quote) or within 4 ULP. How
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

type outcome =
  | Root of float
  | Below
  | Above
  | Expiry
  | Smallest
  | Refused of string

let of_iv to_float = function
  | Iv.Root v -> Root (to_float v)
  | Iv.Below_intrinsic -> Below
  | Iv.Above_maximum -> Above
  | Iv.Not_identifiable_at_expiry -> Expiry
  | Iv.Below_smallest_volatility -> Smallest

let refused (Refusal.Invalid_input { parameter; _ }) =
  Refused (parameter_name parameter)

let solve model side ~s ~k ~t ~r ~q ~shift ~target =
  let lift admit implied to_float =
    match admit with
    | Error e -> refused e
    | Ok a -> (
        match implied a side target with
        | Ok iv -> of_iv to_float iv
        | Error e -> refused e)
  in
  match model with
  | "bsm" ->
      lift
        (Black.Bsm.admit
           {
             spot = s;
             strike = k;
             time_to_expiry = t;
             rate = r;
             dividend_yield = q;
           })
        Black.Bsm.implied Vol.to_float
  | "black76" ->
      lift
        (Black.Black76.admit
           { forward = s; strike = k; time_to_expiry = t; rate = r })
        Black.Black76.implied Vol.to_float
  | "displaced" ->
      lift
        (Black.Displaced.admit
           {
             forward = s;
             strike = k;
             displacement = shift;
             time_to_expiry = t;
             rate = r;
           })
        Black.Displaced.implied Vol.to_float
  | "bachelier" ->
      lift
        (Bachelier.admit
           { forward = s; strike = k; time_to_expiry = t; rate = r })
        Bachelier.implied Vol.to_float
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

(* The Black family's implied-volatility error bound, per root
   (docs/error-analysis.md §6), derived from the code path. The quote is
   exact; the inverse forms β, or β̄ = b_max - β near the maximum, from the
   double-word legs and rounds it once (u), then takes one Newton step against
   the kernel. LBR's two Householder steps leave the start accurate to working
   precision (Jäckel 2015, 2024), so the step's quadratic term is below u².
   With s the exact normalised root and b' = ∂b/∂s, the relative error in σ
   is at most

     3u + (δβ + κ) · c,

   where δβ = u below the money; in the money β = (quote - I)/m carries the
   intrinsic's double-word error E_I (Bounds.intrinsic_error), so
   δβ = u + (E_I + 3u² quote)/(quote - I), and

   3u covers σ = s / sqrt T with sqrt T's low part. By branch:
   - β <= b_max/2: c = b/(s b') and κ = 64u, the kernel's component bound
     (the price oracle's enforced 32 ULP for out-of-the-money values);
   - β > b_max/2: c = b̄/(s b') and κ = 17u: b̄ = ½ e^-(h²+t²)/2 (erfcx(q1) +
     erfcx(q2)) with q1, q2 >= 0 there (s² > 2|x|), so 8u from erfcx's
     4-ULP component bound, 3u from the arguments, u for the sum and 5u
     for the scaled exponential;
   - β < 2^-900 (Newton on ln b): c = b/(s b') times the absolute error in
     ln β - ln b, from Elementary.log (1 ULP each) and the kernel (64u). *)
let black_root_bound model ~side_call ~s ~k ~t ~r ~q ~shift ~quote ~root =
  let u = 0x1p-53 in
  let s' = s +. shift and k' = k +. shift in
  let q' = if model = "bsm" then q else r in
  let x = -.Float.abs (Float.log (s' /. k') +. ((r -. q') *. t)) in
  let sd = root *. Float.sqrt t in
  if not (sd > 0.0 && Float.is_finite sd) then Float.infinity
  else
    let ln_b, bx = Internal.Normalised_black.ln_b_and_scaled x 0.0 sd in
    let c_b = bx /. sd in
    let h = x /. sd and half = 0.5 *. sd in
    let c_bar =
      Internal.Normalised_black.sqrt_two_pi *. 0.5
      *. (Internal.Cody.erfcx ((half +. h) *. Float.sqrt 0.5)
         +. Internal.Cody.erfcx ((half -. h) *. Float.sqrt 0.5))
      /. sd
    in
    (* β = (quote - I⁺)/m: below the money I⁺ = 0; in the money the
       intrinsic's double-word error E_I is divided by quote - I, the
       out-of-the-money part, m b(x, s). *)
    let a = s' *. Float.exp (-.q' *. t) and c = k' *. Float.exp (-.r *. t) in
    let itm = (if side_call then a -. c else c -. a) > 0.0 in
    let otm = Float.sqrt a *. Float.sqrt c *. Float.exp ln_b in
    let d_beta =
      if itm then
        let e_i =
          Bounds.intrinsic_error model ~s ~k ~t ~r ~q ~shift ~reference:0.0
        in
        u +. ((e_i +. (3.0 *. Bounds.u2 *. quote)) /. otm)
      else u
    in
    let linear = (3.0 *. u) +. ((d_beta +. (64.0 *. u)) *. c_b) in
    let complement = (3.0 *. u) +. ((d_beta +. (17.0 *. u)) *. c_bar) in
    let logarithmic =
      let exponent = (snd (Float.frexp s') + snd (Float.frexp k')) asr 1 in
      let a = s' *. Float.exp (-.q' *. t) and c = k' *. Float.exp (-.r *. t) in
      let ln_m =
        (0.5 *. (Float.log a +. Float.log c))
        -. (float exponent *. Float.log 2.0)
      in
      let ln_error =
        3.0 *. u
        *. (Float.abs (Float.log quote)
           +. Float.abs (float exponent *. Float.log 2.0)
           +. Float.abs ln_m)
        +. (64.0 *. u)
        +. (2.0 *. u *. Float.abs ln_b)
      in
      (3.0 *. u) +. (ln_error *. c_b)
    in
    let ln_half_max = (0.5 *. x) -. Float.log 2.0
    and ln_small = -900.0 *. Float.log 2.0 in
    (* Within a hair of a threshold the exact β cannot say which branch the
       rounded β took. *)
    let near a b = Float.abs (a -. b) <= 1e-6 *. Float.max 1.0 (Float.abs b) in
    let candidates =
      (if ln_b > ln_half_max || near ln_b ln_half_max then [ complement ]
       else [])
      @ (if ln_b < ln_small || near ln_b ln_small then [ logarithmic ] else [])
      @
      if
        (ln_b <= ln_half_max && ln_b >= ln_small)
        || near ln_b ln_half_max || near ln_b ln_small
      then [ linear ]
      else []
    in
    List.fold_left Float.max 0.0 candidates

let () =
  let stats = Hashtbl.create 32 in
  let unresolved = Hashtbl.create 8 in
  let failures = ref [] in
  let ic = open_in Sys.argv.(1) in
  (try
     while true do
       let line = input_line ic in
       if line <> "" && line.[0] <> '#' then
         Scanf.sscanf line
           "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
           (fun
             model
             side
             status
             param
             s
             k
             t
             r
             q
             _sigma
             shift
             target
             lo
             hi
             root
             ferro
           ->
             let s = f s
             and k = f k
             and t = f t
             and r = f r
             and q = f q
             and shift = f shift in
             let target = f target
             and lo = f lo
             and hi = f hi
             and root = f root
             and ferro = f ferro in
             let side = if side = "call" then Side.Call else Side.Put in
             let got = solve model side ~s ~k ~t ~r ~q ~shift ~target in
             let key = model ^ " " ^ status in
             let st =
               match Hashtbl.find_opt stats key with
               | Some st -> st
               | None ->
                   let st =
                     {
                       n = 0;
                       pass = 0;
                       in_cell = 0;
                       within_4 = 0;
                       within_ferro = 0;
                       worst_ulp = 0.0;
                     }
                   in
                   Hashtbl.add stats key st;
                   st
             in
             let record ok =
               st.n <- st.n + 1;
               if ok then st.pass <- st.pass + 1
             in
             let fail expected =
               if List.length !failures < 30 then
                 failures :=
                   Printf.sprintf "%s %s: expected %s, got %s | %s" model status
                     expected (show got) line
                   :: !failures
             in
             match status with
             | "root" -> (
                 match got with
                 | Root v ->
                     let in_cell =
                       (Float.is_nan lo || v >= lo)
                       && (Float.is_nan hi || v <= hi)
                     in
                     let u = ulps v root in
                     let within_ferro = Float.abs (v -. root) <= ferro in
                     if in_cell then st.in_cell <- st.in_cell + 1;
                     if u <= 4.0 then st.within_4 <- st.within_4 + 1;
                     if within_ferro then st.within_ferro <- st.within_ferro + 1;
                     if u > st.worst_ulp then st.worst_ulp <- u;
                     (* Enforced. The Black family: the derived bound above,
                        plus half an ULP for the reference's own rounding.
                        Bachelier's bound is not yet derived (see the CHANGELOG);
                        it keeps the rounding cell or 4 ULP. *)
                     let ok =
                       if model = "bachelier" then in_cell || u <= 4.0
                       else
                         let rel =
                           black_root_bound model ~side_call:(side = Side.Call)
                             ~s ~k ~t ~r ~q ~shift ~quote:target ~root
                         in
                         Float.abs (v -. root)
                         <= (rel *. root) +. (0.5 *. Bounds.ulp root)
                     in
                     record ok;
                     if not ok then
                       fail (Printf.sprintf "Root %h in [%h, %h]" root lo hi)
                 | _ ->
                     record false;
                     fail (Printf.sprintf "Root %h" root))
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
                 let representable =
                   not (param = "dividend_yield" && model <> "bsm")
                 in
                 let ok = if representable then got = Refused param else true in
                 record ok;
                 if not ok then fail ("Refused " ^ param)
             | _ ->
                 let k =
                   status ^ " -> "
                   ^ match got with Root _ -> "Root" | o -> show o
                 in
                 Hashtbl.replace unresolved k
                   (1 + Option.value ~default:0 (Hashtbl.find_opt unresolved k)))
     done
   with End_of_file -> close_in ic);
  Printf.printf "%-44s %5s %5s %8s %6s %8s %10s\n" "model status" "rows" "pass"
    "in cell" "<=4ulp" "<=ferro" "worst ulp";
  Hashtbl.fold (fun k _ acc -> k :: acc) stats []
  |> List.sort compare
  |> List.iter (fun key ->
         let st = Hashtbl.find stats key in
         let root = String.ends_with ~suffix:"root" key in
         let show n = if root then string_of_int n else "" in
         Printf.printf "%-44s %5d %5d %8s %6s %8s %10s\n" key st.n st.pass
           (show st.in_cell) (show st.within_4) (show st.within_ferro)
           (if root then Printf.sprintf "%.0f" st.worst_ulp else ""));
  Printf.printf "unresolved reference rows (no expectation):\n";
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) unresolved []
  |> List.sort compare
  |> List.iter (fun (k, v) -> Printf.printf "  %-60s %d\n" k v);
  List.iter print_endline (List.rev !failures);
  if !failures <> [] then exit 1
