open Morphiq_risk
module E = Internal.Enclosure
module M = Internal.Model_enclosure

let power2 n =
  if n >= 0 then Q.of_bigint (Z.shift_left Z.one n)
  else Q.make Z.one (Z.shift_left Z.one (-n))

let centre (a : E.t) =
  List.fold_left (fun sum x -> Q.add sum (Q.of_float x)) Q.zero (E.words a)

let check label result reference uncertainty =
  let discrepancy = Q.abs (Q.sub (centre result) reference) in
  if Q.compare discrepancy (Q.add (Q.of_float result.E.error) uncertainty) > 0
  then
    failwith
      (Printf.sprintf "%s: real model outside enclosure (%h,%h) +/- %h" label
         result.hi result.lo result.error)

let () =
  let rows = ref 0 in
  In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line
             "%s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
             (fun model side family s k t r q sigma shift exponent h l tail ->
               let f = Int64.float_of_bits in
               let s, k, t, r, q, sigma, shift =
                 (f s, f k, f t, f r, f q, f sigma, f shift)
               in
               let side = if side = "call" then Side.Call else Side.Put in
               let prepared =
                 if model = "bachelier" then
                   M.normal ~forward:s ~strike:k ~time:t ~rate:r
                 else
                   let shifted value = E.add (E.exact value) (E.exact shift) in
                   let sp = shifted s and st = shifted k in
                   if sp.error <> 0.0 || st.error <> 0.0 then
                     failwith "inexact input sum";
                   M.black ~spot:sp.hi ~spot_low:sp.lo ~strike:st.hi
                     ~strike_low:st.lo ~time:t ~rate:r
                     ~yield:(if model = "bsm" then q else r)
               in
               let result = M.price prepared side sigma in
               let factor = power2 exponent in
               let reference =
                 Q.mul factor
                   (Q.add
                      (Q.add (Q.of_float (f h)) (Q.of_float (f l)))
                      (Q.of_float (f tail)))
               in
               check
                 (model ^ "/" ^ family)
                 result reference
                 (Q.mul factor (power2 (-158)));
               incr rows));
  if !rows = 0 then failwith "empty model enclosure corpus";
  let rejected f =
    match f () with _ -> false | exception E.Unresolved _ -> true
  in
  if
    not
      (rejected (fun () ->
           M.normal ~forward:Float.max_float ~strike:(-.Float.max_float)
             ~time:1.0 ~rate:0.0))
  then failwith "overflowed normal coordinates accepted";
  if
    not
      (rejected (fun () ->
           M.normal ~forward:1.0 ~strike:1.0 ~time:1.0 ~rate:Float.max_float))
  then failwith "unsupported discount accepted";
  if
    not
      (rejected (fun () ->
           M.black ~spot:0.0 ~spot_low:0.0 ~strike:1.0 ~strike_low:0.0 ~time:1.0
             ~rate:0.0 ~yield:0.0))
  then failwith "nonpositive lognormal coordinate accepted";
  Printf.printf
    "%d original-input model enclosures; explicit domain/overflow failures \
     checked\n"
    !rows
