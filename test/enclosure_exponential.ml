open Morphiq_risk.Internal

module Check (E : Enclosure.S) = struct
  let encode f =
    try
      let a = f () in
      "ok:"
      ^ String.concat ":"
          (List.map
             (fun x -> Printf.sprintf "%016Lx" (Int64.bits_of_float x))
             [ a.E.hi; a.lo; a.third; a.fourth; a.error ])
    with E.Unresolved why -> "error:" ^ why

  let centre (a : E.t) =
    List.fold_left (fun s x -> Q.add s (Q.of_float x)) Q.zero (E.words a)

  (* For |x| <= 1, Taylor degree 96 has absolute remainder at most
     3 |x|^97/97!: exp(|x|) <= e < 3. Exact rationals are independent of
     the production range reduction, floating series and squaring graph. *)
  let reference x minus_one =
    if Q.compare (Q.abs x) Q.one > 0 then invalid_arg "reference domain";
    let sum = ref Q.one and term = ref Q.one in
    for n = 1 to 96 do
      term := Q.div (Q.mul !term x) (Q.of_int n);
      sum := Q.add !sum !term
    done;
    let radius =
      Q.mul (Q.of_int 3) (Q.abs (Q.div (Q.mul !term x) (Q.of_int 97)))
    in
    let value = if minus_one then Q.sub !sum Q.one else !sum in
    (Q.sub value radius, Q.add value radius)

  let independent a minus_one =
    let result = (if minus_one then E.expm1 else E.exp) a in
    let c = centre a and radius = Q.of_float a.E.error in
    let lo, _ = reference (Q.sub c radius) minus_one
    and _, hi = reference (Q.add c radius) minus_one in
    let rc = centre result and rr = Q.of_float result.E.error in
    if Q.compare (Q.sub rc rr) lo > 0 || Q.compare (Q.add rc rr) hi < 0 then
      failwith "exponential independent rational containment"

  let run label =
    let words =
      [
        0.;
        -0.;
        0x1p-1074;
        -0x1p-1074;
        Float.min_float;
        -.Float.min_float;
        0x1p-500;
        -0x1p-500;
        0x1p-54;
        -0x1p-54;
        0.125;
        -0.125;
        1.;
        -1.;
        16.;
        -16.;
        Float.pred 256.;
        256.;
        Float.succ 256.;
        Float.succ (-256.);
        -256.;
        Float.pred (-256.);
      ]
    in
    let rng = Random.State.make [| 20261006; 119; 147 |] in
    let cases = ref (List.map E.exact words) in
    for _ = 1 to 512 do
      let x = Random.State.float rng 512. -. 256. in
      let low = Float.ldexp x (-54) *. (Random.State.float rng 2. -. 1.) in
      cases := E.of_words x low :: !cases;
      cases := E.add_error (E.of_words x low) 0x1p-60 :: !cases
    done;
    let replay = Buffer.create 4096 in
    let evaluate a =
      List.iter
        (fun f ->
          Buffer.add_string replay (encode (fun () -> f a));
          Buffer.add_char replay '\n')
        [ E.exp; E.expm1 ]
    in
    List.iter evaluate !cases;
    let retained =
      List.map
        (fun x -> (E.exp (E.exact x), E.expm1 (E.exact x)))
        [ 0.125; -0.25; 16.; -16. ]
    in
    let before =
      List.map
        (fun (a, b) -> (encode (fun () -> a), encode (fun () -> b)))
        retained
    in
    List.iter evaluate !cases;
    ignore (encode (fun () -> E.exp (E.exact 257.)));
    Gc.full_major ();
    if
      before
      <> List.map
           (fun (a, b) -> (encode (fun () -> a), encode (fun () -> b)))
           retained
    then failwith "retained exponential result changed";
    let concurrent () =
      List.map (fun x -> encode (fun () -> E.expm1 (E.exact x))) words
    in
    let expected = concurrent () in
    let workers = Array.init 4 (fun _ -> Domain.spawn concurrent) in
    Array.iter
      (fun d ->
        if Domain.join d <> expected then
          failwith "exponential domain ownership")
      workers;
    let count = ref 0 in
    for k = -15 to 15 do
      List.iter
        (fun error ->
          let a = E.add_error (E.exact (float k /. 16.)) error in
          List.iter
            (fun minus_one ->
              independent a minus_one;
              incr count)
            [ false; true ])
        [ 0.; 0x1p-40 ]
    done;
    Printf.printf "%s cases=%d rational=%d replay=%s\n%!" label
      (List.length !cases) !count
      (Digest.to_hex (Digest.string (Buffer.contents replay)))
end

module Full = Check (Enclosure)
module Fast = Check (Enclosure.Fast)

let () =
  Full.run "full";
  Fast.run "fast"
