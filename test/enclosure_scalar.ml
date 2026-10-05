open Morphiq_risk.Internal

module Check (E : Enclosure.S) = struct
  let words (a : E.t) =
    List.map Int64.bits_of_float [ a.hi; a.lo; a.third; a.fourth; a.error ]

  let capture f = try Ok (f ()) with E.Unresolved reason -> Error reason

  let same label lhs rhs =
    let encode = Result.map words in
    if encode lhs <> encode rhs then failwith (label ^ " complete-word mismatch")

  let centre a =
    List.fold_left (fun q x -> Q.add q (Q.of_float x)) Q.zero (E.words a)

  let endpoints (a : E.t) =
    let c = centre a and radius = Q.of_float a.error in
    [ Q.sub c radius; Q.add c radius ]

  let contains label reference result =
    if
      Q.compare
        (Q.abs (Q.sub (centre result) reference))
        (Q.of_float result.E.error)
      > 0
    then failwith (label ^ " exact-rational enclosure failure")

  let run label =
    let checks = ref 0 and rational = ref 0 and refused = ref 0 in
    let replay = Buffer.create 4096 in
    let retain = function
      | Error reason ->
          incr refused;
          Buffer.add_string replay ("error:" ^ reason ^ "\n")
      | Ok value ->
          List.iter
            (fun x -> Buffer.add_string replay (Printf.sprintf "%016Lx" x))
            (words value);
          Buffer.add_char replay '\n'
    in
    let scalar a b =
      let expected = capture (fun () -> E.mul a (E.exact b))
      and observed = capture (fun () -> E.mul_float a b) in
      retain observed;
      incr checks;
      (match observed with
      | Error _ -> ()
      | Ok result ->
          List.iter
            (fun x ->
              contains "scalar product" (Q.mul x (Q.of_float b)) result;
              incr rational)
            (endpoints a));
      same "scalar product" expected observed;
      let expected = capture (fun () -> E.magnitude (E.sub a (E.exact b)))
      and observed = capture (fun () -> E.error_of_float a b) in
      if
        Result.map Int64.bits_of_float expected
        <> Result.map Int64.bits_of_float observed
      then failwith "scalar difference magnitude mismatch";
      if
        capture (fun () -> E.sign (E.sub a (E.exact b)))
        <> capture (fun () -> E.compare_float a b)
      then failwith "scalar comparison mismatch";
      let quotient = capture (fun () -> E.div_float a b) in
      retain quotient;
      match quotient with
      | Error _ -> ()
      | Ok result ->
          List.iter
            (fun x ->
              contains "scalar quotient" (Q.div x (Q.of_float b)) result;
              incr rational)
            (endpoints a)
    in
    let subtract a b =
      let expected = capture (fun () -> E.add a (E.neg b))
      and observed = capture (fun () -> E.sub a b) in
      same "subtraction" expected observed;
      retain observed;
      incr checks;
      match observed with
      | Error _ -> ()
      | Ok result ->
          List.iter
            (fun x ->
              List.iter
                (fun y ->
                  contains "subtraction" (Q.sub x y) result;
                  incr rational)
                (endpoints b))
            (endpoints a)
    in
    let scalars =
      [
        0.;
        -0.;
        1.;
        -1.;
        2.;
        -2.;
        0.1;
        -0.1;
        Float.max_float;
        -.Float.max_float;
        0x1p-1074;
        -0x1p-1074;
        Float.min_float;
        Float.pred Float.min_float;
        Float.pred 0x1p-485;
        0x1p-485;
        Float.succ 0x1p-485;
        0x1p500;
        -0x1p500;
        0x1p-500;
      ]
    in
    let inputs =
      List.map E.exact scalars
      @ [
          E.of_words 1. 0x1p-54;
          E.of_words (-1.) 0x1p-54;
          E.add_error (E.of_words 1. 0x1p-1000) 0x1p-60;
          E.add_error (E.exact 0.) 0x1p-1074;
          E.mul (E.of_words 1. 0x1p-54) (E.of_words 1. 0x1p-107);
        ]
    in
    List.iter
      (fun a ->
        List.iter (scalar a) (scalars @ [ nan; infinity; neg_infinity ]);
        List.iter (subtract a) inputs)
      inputs;
    let rng = Random.State.make [| 119; 20261005 |] in
    for _ = 1 to 2000 do
      let value () =
        let h =
          Float.ldexp
            (1. +. Random.State.float rng 1.)
            (Random.State.int rng 2001 - 1000)
        in
        let h = if Random.State.bool rng then h else -.h in
        E.add_error
          (E.of_words h (Float.ldexp h (-55)))
          (Float.abs (Float.ldexp h (-61)))
      in
      let a = value () and b = value () in
      scalar a b.hi;
      subtract a b
    done;
    (* Retained immutable results must survive later divisions and exceptions.
       Exercise stale tail slots by alternating precisions/operand shapes. *)
    let held = E.div_float (E.of_words 1. 0x1p-54) 3. in
    let original = words held in
    for i = 1 to 100 do
      ignore
        (capture (fun () -> E.div_float (E.exact Float.max_float) 0x1p-1074));
      ignore (E.div_float (E.exact (float i)) 7.);
      if words held <> original then failwith "division scratch escaped"
    done;
    let work () = E.div_float (E.of_words 1. 0x1p-54) 3. |> words in
    let domain = Domain.spawn work in
    if work () <> Domain.join domain then
      failwith "division scratch shared across domains";
    Printf.printf "%s scalar checks=%d rational=%d refused=%d replay=%s\n%!"
      label !checks !rational !refused
      (Digest.to_hex (Digest.string (Buffer.contents replay)))
end

module Full = Check (Enclosure)
module Fast = Check (Enclosure.Fast)

let () =
  Full.run "full";
  Fast.run "fast"
