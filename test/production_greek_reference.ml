open Morphiq_risk
module E = Internal.Enclosure
module M = Internal.Model_enclosure

let power2 n =
  if n >= 0 then Q.of_bigint (Z.shift_left Z.one n)
  else Q.make Z.one (Z.shift_left Z.one (-n))

let sensitivity = function
  | "delta" -> M.Delta
  | "gamma" -> M.Gamma
  | "theta" -> M.Theta
  | "vega" -> M.Vega
  | "rho" -> M.Rho
  | "vanna" -> M.Vanna
  | "volga" -> M.Volga
  | "charm" -> M.Charm
  | "veta" -> M.Veta
  | "color" -> M.Color
  | x -> invalid_arg x

let () =
  let rows = ref 0 and unresolved = ref 0 in
  In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line
             "%s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
             (fun model side name s k t r q sigma shift exponent h l tail ->
               let f = Int64.float_of_bits in
               let s, k, t, r, q, sigma, shift =
                 (f s, f k, f t, f r, f q, f sigma, f shift)
               in
               let side = if side = "call" then Side.Call else Side.Put in
               try
                 let prepared =
                   if model = "bachelier" then
                     M.normal ~forward:s ~strike:k ~time:t ~rate:r
                   else
                     let shifted x =
                       if model = "displaced" then
                         Internal.Split.two_sum x shift
                       else (x, 0.)
                     in
                     let sh, sl = shifted s and kh, kl = shifted k in
                     M.black ~spot:sh ~spot_low:sl ~strike:kh ~strike_low:kl
                       ~time:t ~rate:r
                       ~yield:(if model = "bsm" then q else r)
                 in
                 let result =
                   M.greek prepared side sigma ~rho_forward:(model <> "bsm")
                     (sensitivity name)
                 in
                 let centre =
                   List.fold_left
                     (fun a x -> Q.add a (Q.of_float x))
                     Q.zero (E.words result)
                 in
                 let factor = power2 exponent in
                 let reference =
                   Q.mul factor
                     (List.fold_left
                        (fun a x -> Q.add a (Q.of_float (f x)))
                        Q.zero [ h; l; tail ])
                 in
                 let uncertainty = Q.mul factor (power2 (-158)) in
                 let error = Q.abs (Q.sub centre reference) in
                 if
                   Q.compare error (Q.add (Q.of_float result.error) uncertainty)
                   > 0
                 then failwith ("Greek outside enclosure: " ^ line);
                 incr rows
               with E.Unresolved _ -> incr unresolved));
  Printf.printf
    "%d enclosed extra-bit Greek references, %d explicit capability failures\n"
    !rows !unresolved;
  if !rows = 0 then failwith "empty successful reference coverage"
