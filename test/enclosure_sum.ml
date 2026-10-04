open Morphiq_risk.Internal

module Check (E : Enclosure.S) = struct
  let run () =
    let served = ref 0 and refused = ref 0 in
    let pair a b =
      if Float.is_finite (a +. b) then (
        let result = E.of_words a b in
        if
          result.error <> 0.
          || not (List.for_all Float.is_finite (E.words result))
        then failwith "finite two-word sum lost exactness";
        let actual =
          List.fold_left
            (fun total x -> Q.add total (Q.of_float x))
            Q.zero (E.words result)
        in
        if not (Q.equal actual (Q.add (Q.of_float a) (Q.of_float b))) then
          failwith "two-word sum disagrees with exact rational addition";
        incr served)
      else
        match E.of_words a b with
        | exception E.Unresolved _ -> incr refused
        | _ -> failwith "nonfinite two-word sum was accepted"
    in
    let points =
      [
        0.;
        -0.;
        0x1p-1074;
        Float.pred Float.min_float;
        Float.min_float;
        Float.succ Float.min_float;
        0x1p-53;
        Float.pred 1.;
        1.;
        Float.succ 1.;
        0x1p53;
        0x1p54;
        Float.pred Float.max_float;
        Float.max_float;
      ]
    in
    List.iter
      (fun a ->
        List.iter
          (fun b ->
            pair a b;
            pair (-.a) b;
            pair a (-.b);
            pair (-.a) (-.b))
          points)
      points;
    let rng = Random.State.make [| 20261004; 8; 93 |] in
    let rec finite_word () =
      let x = Int64.float_of_bits (Random.State.bits64 rng) in
      if Float.is_finite x then x else finite_word ()
    in
    for _ = 1 to 10000 do
      let a = finite_word () and b = finite_word () in
      pair a b;
      pair b a;
      pair a (-.a)
    done;
    Printf.printf "exact expansion sums: %d served, %d overflow refusals\n%!"
      !served !refused
end

module Full = Check (Enclosure)
module First = Check (Enclosure.Fast)

let () =
  Full.run ();
  First.run ()
