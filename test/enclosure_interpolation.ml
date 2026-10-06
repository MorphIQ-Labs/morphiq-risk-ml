open Morphiq_risk.Internal

module Check (E : Enclosure.S) = struct
  let original point ~lower ~upper ~left ~right =
    if E.compare_float point lower = E.Zero then E.Endpoint left
    else if E.compare_float point upper = E.Zero then E.Endpoint right
    else
      let width = E.sub (E.exact upper) (E.exact lower) in
      let weight = E.div (E.sub point (E.exact lower)) width in
      match (E.compare_float weight 0., E.compare_float weight 1.) with
      | E.Positive, E.Negative ->
          E.Interpolated
            (E.add
               (E.mul (E.sub (E.exact 1.) weight) (E.exact left))
               (E.mul weight (E.exact right)))
      | _ -> E.Unresolved_weight

  let fields (a : E.t) = [ a.hi; a.lo; a.third; a.fourth; a.error ]

  let floats xs =
    String.concat ":"
      (List.map (fun x -> Printf.sprintf "%016Lx" (Int64.bits_of_float x)) xs)

  let encode f =
    try
      match f () with
      | E.Endpoint x -> "endpoint:" ^ floats [ x ]
      | E.Interpolated a -> "interior:" ^ floats (fields a)
      | E.Unresolved_weight -> "weight"
    with E.Unresolved why -> "error:" ^ why

  let centre a =
    List.fold_left (fun s x -> Q.add s (Q.of_float x)) Q.zero (E.words a)

  let independent point ~lower ~upper ~left ~right =
    let l = Q.of_float lower and u = Q.of_float upper in
    let pl = Q.sub (centre point) (Q.of_float point.E.error)
    and pu = Q.add (centre point) (Q.of_float point.E.error) in
    if Q.compare l u >= 0 || Q.compare pl l < 0 || Q.compare pu u > 0 then
      invalid_arg "independent interpolation domain";
    let evaluate p =
      let weight = Q.div (Q.sub p l) (Q.sub u l) in
      Q.add
        (Q.mul (Q.sub Q.one weight) (Q.of_float left))
        (Q.mul weight (Q.of_float right))
    in
    let a = evaluate pl and b = evaluate pu in
    let lo = Q.min a b and hi = Q.max a b in
    let rc, rr =
      match E.linear_interpolate point ~lower ~upper ~left ~right with
      | E.Endpoint x -> (Q.of_float x, Q.zero)
      | E.Interpolated x -> (centre x, Q.of_float x.E.error)
      | E.Unresolved_weight -> failwith "interpolation independent availability"
    in
    if Q.compare (Q.sub rc rr) lo > 0 || Q.compare (Q.add rc rr) hi < 0 then
      failwith "interpolation independent rational containment"

  let numerical () =
    let count = ref 0 in
    for k = 1 to 31 do
      List.iter
        (fun error ->
          List.iter
            (fun (left, right) ->
              independent
                (E.add_error (E.exact (float k /. 32.)) error)
                ~lower:0. ~upper:1. ~left ~right;
              independent
                (E.add_error (E.exact (float k /. 32.)) error)
                ~lower:(-1e-20) ~upper:1. ~left ~right;
              count := !count + 2)
            [ (0., 1.); (3., 7.); (-3., 2.); (1e100, -1e100) ])
        [ 0.; 0x1p-40 ]
    done;
    !count

  let run label =
    let count = numerical () in
    if Array.length Sys.argv > 1 && Sys.argv.(1) = "--numerical-only" then
      Printf.printf "%s rational=%d\n%!" label count
    else
      let cases = ref [] in
      let add point lower upper left right =
        cases := (point, lower, upper, left, right) :: !cases
      in
      List.iter
        (fun (l, u) ->
          List.iter
            (fun p ->
              List.iter
                (fun (a, b) -> add (E.exact p) l u a b)
                [
                  (0., -0.); (1., -1.); (0x1p-1074, 0x1p-1022); (1e200, 1e-200);
                ])
            [ l; u; l +. ((u -. l) /. 2.); Float.succ l; Float.pred u ])
        [
          (0., 1.);
          (-1., 0.);
          (1., Float.succ 1.);
          (0., 0x1p-1073);
          (0x1p-1022, 0x1p-1021);
          (-1e100, 1e100);
          (1., 1.);
          (2., 1.);
        ];
      let rng = Random.State.make [| 20261006; 119; 148 |] in
      for _ = 1 to 512 do
        let l = Random.State.float rng 256. -. 128. in
        let width = 0.01 +. Random.State.float rng 8. in
        let u = l +. width in
        let p = l +. (Random.State.float rng 1. *. width) in
        let point = E.of_words p (Float.ldexp p (-54)) in
        let a = Random.State.float rng 200. -. 100.
        and b = Random.State.float rng 200. -. 100. in
        add point l u a b;
        add (E.add_error point 0x1p-40) l u a b
      done;
      List.iter
        (fun p -> add (E.add_error (E.exact p) 0.1) 0. 1. 3. 7.)
        [ -1.; 0.; 0.5; 1.; 2. ];
      add (E.exact 0.) 0. 1. (-0.) nan;
      add (E.exact 1.) 0. 1. nan (-0.);
      add (E.exact 0.5) 0. infinity 1. 2.;
      let replay = Buffer.create 4096 in
      let calculate f (point, lower, upper, left, right) =
        f point ~lower ~upper ~left ~right
      in
      List.iter
        (fun c ->
          let expected = encode (fun () -> calculate original c)
          and actual = encode (fun () -> calculate E.linear_interpolate c) in
          if expected <> actual then
            failwith "interpolation full-field compatibility";
          Buffer.add_string replay actual;
          Buffer.add_char replay '\n')
        !cases;
      let retained =
        List.map
          (fun p ->
            E.linear_interpolate (E.exact p) ~lower:0. ~upper:1. ~left:3.
              ~right:7.)
          [ 0.; 0.125; 0.5; 1. ]
      in
      let snapshot () = List.map (fun x -> encode (fun () -> x)) retained in
      let before = snapshot () in
      List.iter
        (fun c -> ignore (encode (fun () -> calculate E.linear_interpolate c)))
        !cases;
      Gc.full_major ();
      if snapshot () <> before then failwith "retained interpolation changed";
      let concurrent () =
        List.map
          (fun c -> encode (fun () -> calculate E.linear_interpolate c))
          !cases
      in
      let expected = concurrent () in
      let workers = Array.init 4 (fun _ -> Domain.spawn concurrent) in
      Array.iter
        (fun d ->
          if Domain.join d <> expected then
            failwith "interpolation domain ownership")
        workers;
      Printf.printf "%s cases=%d rational=%d replay=%s\n%!" label
        (List.length !cases) count
        (Digest.to_hex (Digest.string (Buffer.contents replay)))
end

module Full = Check (Enclosure)
module Fast = Check (Enclosure.Fast)

let () =
  Full.run "full";
  Fast.run "fast"
