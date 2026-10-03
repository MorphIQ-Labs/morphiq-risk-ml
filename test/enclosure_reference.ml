open Morphiq_risk.Internal
module E = Enclosure

let q = Q.of_float
let centre (a : E.t) = Q.add (q a.hi) (q a.lo)
let lower a = Q.sub (centre a) (q a.E.error)
let upper a = Q.add (centre a) (q a.E.error)
let endpoints a = [ lower a; upper a ]

let check label reference radius result =
  if
    Q.compare
      (Q.abs (Q.sub (centre result) reference))
      (Q.add (q result.E.error) radius)
    > 0
  then
    failwith
      (Printf.sprintf "%s enclosure failed: (%h,%h) +/- %h" label result.E.hi
         result.lo result.error)

let binary label op eval a b =
  let result = eval a b in
  List.iter
    (fun av ->
      List.iter (fun bv -> check label (op av bv) Q.zero result) (endpoints b))
    (endpoints a)

let power2 n =
  if n >= 0 then Q.of_bigint (Z.shift_left Z.one n)
  else Q.make Z.one (Z.shift_left Z.one (-n))

let sqrt_check a =
  let result = E.sqrt a in
  let lo = Q.max Q.zero (lower result) and hi = upper result in
  if
    Q.sign hi < 0
    || Q.compare (Q.mul lo lo) (lower a) > 0
    || Q.compare (Q.mul hi hi) (upper a) < 0
  then failwith "square-root enclosure failed"

let () =
  let cases = ref 0 in
  let points =
    List.map E.exact
      [
        0.0;
        0x1p-1074;
        Float.min_float;
        0x1.0000000000001p-537;
        0x1p-500;
        0.1;
        1.0;
        Float.succ 1.0;
        3.0;
        0x1p500;
      ]
    @ [
        E.of_words 1.0 0x1p-1000;
        E.of_words 1.0 (-0x1p-54);
        E.of_words 0x1p500 0x1p-1000;
        E.mul (E.exact 0.1) (E.exact 0.3);
      ]
  in
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          List.iter
            (fun (name, op, eval) ->
              binary name op eval a b;
              binary name op eval (E.neg a) b;
              incr cases)
            [
              ("add", Q.add, E.add); ("sub", Q.sub, E.sub); ("mul", Q.mul, E.mul);
            ];
          if Q.sign (lower b) > 0 then
            (* A quotient outside the finite representation is an explicit
               unsupported case, rather than a finite enclosure claim. *)
            let max = q Float.max_float in
            if
              List.for_all
                (fun av ->
                  List.for_all
                    (fun bv -> Q.compare (Q.abs (Q.div av bv)) max < 0)
                    (endpoints b))
                (endpoints a)
            then (
              binary "div" Q.div E.div a b;
              incr cases))
        points;
      if Q.sign (lower a) > 0 then sqrt_check a;
      List.iter
        (fun k ->
          let factor = power2 k in
          let reference = Q.mul (centre a) factor in
          if Q.compare (Q.abs reference) (q Float.max_float) < 0 then
            let scaled = E.scale a k in
            List.iter
              (fun av -> check "scale" (Q.mul av factor) Q.zero scaled)
              (endpoints a))
        [ -1074; -100; 0; 100; 500 ])
    points;
  let rng = Random.State.make [| 20261002; 27; 14 |] in
  for _ = 1 to 2000 do
    let value () =
      let h =
        Float.ldexp
          (1.0 +. Random.State.float rng 1.0)
          (Random.State.int rng 1001 - 500)
      in
      let l = Float.ldexp h (-54) *. (Random.State.float rng 2.0 -. 1.0) in
      E.of_words h l
    in
    let a = value () and b = value () in
    binary "random add" Q.add E.add a b;
    binary "random mul" Q.mul E.mul a b;
    binary "random div" Q.div E.div a b;
    sqrt_check a
  done;
  let rejected f =
    match f () with _ -> false | exception E.Unresolved _ -> true
  in
  if not (rejected (fun () -> E.exp (E.exact 257.0))) then
    failwith "exponential domain not enforced";
  if not (rejected (fun () -> E.div (E.exact 1.0) (E.exact 0.0))) then
    failwith "unresolved denominator accepted";
  if not (rejected (fun () -> E.exact Float.nan)) then
    failwith "nonfinite enclosure accepted";
  let rows = ref 0 and outside_exp = ref 0 and other_functions = ref 0 in
  In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line "%s %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
             (fun fn ah al _bh _bl exponent h l tail ->
               let f = Int64.float_of_bits in
               let a = E.of_words (f ah) (f al) in
               let evaluated =
                 match fn with
                 | ("exp" | "expm1") when E.magnitude a > 256.0 ->
                     incr outside_exp;
                     None
                 | "exp" -> Some (E.exp a)
                 | "expm1" -> Some (E.expm1 a)
                 | "log" -> Some (E.log (E.exact (f ah)))
                 | "normal_pdf" -> Some (Model_enclosure.pdf a)
                 | "normal_cdf" -> Some (Model_enclosure.cdf a)
                 | "sqrt" -> Some (E.sqrt a)
                 | "split_sqrt" -> Some (E.sqrt (E.exact (f ah)))
                 | _ ->
                     incr other_functions;
                     None
               in
               match evaluated with
               | None -> ()
               | Some result ->
                   let factor = power2 exponent in
                   let reference =
                     Q.mul factor
                       (Q.add (Q.add (q (f h)) (q (f l))) (q (f tail)))
                   in
                   check fn reference (Q.mul factor (power2 (-158))) result;
                   incr rows));
  if !rows = 0 then failwith "empty enclosure reference corpus";
  Printf.printf
    "%d deterministic primitive cases, 2000 random compositions, %d elementary \
     references; %d outside exponential guard; %d other-function rows\n"
    !cases !rows !outside_exp !other_functions
