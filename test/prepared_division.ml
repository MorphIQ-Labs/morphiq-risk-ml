(* Canonical operation compatibility plus independent exact-rational replay. *)
module D = Morphiq_risk.Internal.Dd
module C = Certified.Dd

let same a b =
  Int64.bits_of_float a.D.hi = Int64.bits_of_float b.D.hi
  && Int64.bits_of_float a.D.lo = Int64.bits_of_float b.D.lo

let prepare f b =
  match f b with Some p -> p | None -> failwith "valid divisor rejected"

let cases = ref 0

let check a b =
  let prepared = prepare D.prepare_divisor b in
  if not (same (D.prepared_divisor_value prepared) b) then
    failwith "divisor changed";
  let canonical = D.div a b in
  let got = D.div_prepared a prepared in
  let checked = C.div_prepared a (prepare C.prepare_divisor b) in
  if not (same canonical got && same got checked) then
    failwith
      (Printf.sprintf "prepared quotient differs: (%h,%h) / (%h,%h)" a.hi a.lo
         b.hi b.lo);
  incr cases

let () =
  List.iter
    (fun x ->
      if Option.is_some (D.prepare_divisor (D.of_float x)) then
        failwith "invalid divisor admitted")
    [ 0.; -0.; Float.nan; Float.infinity; Float.neg_infinity ];
  for i = 0 to 399 do
    let b = D.of_float (float ((2 * i) + 3)) in
    List.iter
      (fun exponent ->
        let hi = Float.ldexp (if i land 1 = 0 then 1.5 else -1.5) exponent in
        let lo = Float.ldexp hi (-54) in
        check { D.hi; lo } b)
      [ -1074; -1022; -401; -400; -1; 0; 1; 400; 401; 1023 ];
    check (D.of_float (if i land 1 = 0 then 0. else -0.)) b
  done;
  List.iter
    (fun denominator ->
      let b = D.of_float denominator in
      List.iter
        (fun threshold ->
          List.iter
            (fun hi -> check { D.hi; lo = Float.ldexp hi (-54) } b)
            [ Float.pred threshold; threshold; Float.succ threshold ])
        [ 0x1p-400; 0x1p400; -0x1p-400; -0x1p400 ])
    [ 3.; 5.; 7.; 801. ];
  List.iter
    (fun exponent ->
      List.iter
        (fun sign ->
          let hi = Float.ldexp sign exponent in
          let b = { D.hi; lo = Float.ldexp hi (-54) } in
          check { D.hi = 1.; lo = -0x1p-54 } b;
          check (D.of_float (Float.ldexp 1. (exponent - 74))) b)
        [ 1.; -1. ])
    [ -1000; -400; 0; 400; 1000 ];
  Printf.printf
    "%d prepared quotients: canonical words and independent rational \
     allowances agree\n"
    !cases
