open Morphiq_fp
open Morphiq_risk
module K = Internal.American_residual

let expect label b = if not b then failwith label
let maxf (a : float) (b : float) = if a >= b then a else b
let minf (a : float) (b : float) = if a <= b then a else b
let bits = Int64.bits_of_float
let eta = Float.next_after 0. infinity

(* Independent execution of the pre-existing OCaml operation graph, including
   partial state and finite-check order; products use the original FP boundary. *)
let reference bands ~first ~last ~obstacle metrics indices =
  let lo = bands.(0) and diag = bands.(1) and hi = bands.(2) in
  let rhs = bands.(3) and v = bands.(4) and g = bands.(5) in
  let status = ref 0 and i = ref first in
  indices.(2) <- 0;
  while !i <= last && !status = 0 do
    let j = !i in
    indices.(2) <- indices.(2) + 1;
    let p =
      Float.fma lo.(j)
        v.(j - 1)
        (Float.fma diag.(j) v.(j) (Float.fma hi.(j) v.(j + 1) (-.rhs.(j))))
    in
    let e = v.(j) -. g.(j) in
    let r =
      if obstacle then maxf (abs_float (minf p e)) (maxf (-.p) (-.e))
      else abs_float p
    in
    if not (Float.is_finite r) then status := 1
    else (
      if r > metrics.(0) then (
        metrics.(0) <- r;
        indices.(1) <- j);
      let magnitude =
        abs_float (lo.(j) *. v.(j - 1))
        +. abs_float (diag.(j) *. v.(j))
        +. abs_float (hi.(j) *. v.(j + 1))
        +. abs_float rhs.(j)
        +. abs_float v.(j)
        +. abs_float g.(j)
      in
      let screen = (0x1p-48 *. magnitude) +. (32. *. eta) in
      if not (Float.is_finite screen) then status := 2
      else metrics.(1) <- maxf metrics.(1) screen);
    incr i
  done;
  !status

let check bands =
  let n = Array.length bands.(0) in
  let state =
    K.create ~lo:bands.(0) ~diag:bands.(1) ~hi:bands.(2) ~rhs:bands.(3)
      ~values:bands.(4) ~payoff:bands.(5)
  in
  let before = Array.map (Array.map bits) bands in
  List.iter
    (fun obstacle ->
      List.iter
        (fun chunk ->
          K.reset state ~obstacle;
          let metrics = Array.make 2 0. and indices = Array.make 3 0 in
          let first = ref 1 and status = ref 0 in
          while !first < n - 1 && !status = 0 do
            let last = min (n - 2) (!first + chunk - 1) in
            let expected =
              reference bands ~first:!first ~last ~obstacle metrics indices
            in
            let actual = K.run state ~first:!first ~last in
            expect "residual finite-check order" (actual = expected);
            expect "residual actually visited rows"
              (K.visited state = indices.(2));
            expect "residual first worst row" (K.worst_row state = indices.(1));
            expect "residual operation graph"
              (bits (K.worst state) = bits metrics.(0));
            expect "roundoff operation graph"
              (bits (K.indicator state) = bits metrics.(1));
            status := actual;
            first := last + 1
          done)
        [ 1; 7; 255; 256 ])
    [ false; true ];
  expect "borrowed inputs unchanged" (Array.map (Array.map bits) bands = before)

external raw :
  float array array -> int -> int -> float array -> int array -> int
  = "morphiq_american_residual"

external wrong_tag :
  int array array -> int -> int -> float array -> int array -> int
  = "morphiq_american_residual"

let rejects label f =
  let rejected =
    try
      ignore (f ());
      false
    with Invalid_argument _ -> true
  in
  expect label rejected

let () =
  let bands n = Array.init 6 (fun _ -> Array.make n 0.) in
  let ordinary = bands 514 in
  for i = 0 to 513 do
    ordinary.(0).(i) <- -0.125;
    ordinary.(1).(i) <- 1.25;
    ordinary.(2).(i) <- -0.125;
    ordinary.(3).(i) <- float (i mod 13);
    ordinary.(4).(i) <- float (i mod 17);
    ordinary.(5).(i) <- float (i mod 7)
  done;
  check ordinary;
  let fused = bands 3 in
  fused.(2).(1) <- 1. +. 0x1p-27;
  fused.(4).(2) <- 1. -. 0x1p-27;
  fused.(3).(1) <- 1.;
  check fused;
  let zero = bands 4 in
  zero.(4).(1) <- -0.;
  zero.(5).(2) <- -0.;
  check zero;
  let tiny = bands 4 in
  tiny.(1).(1) <- eta;
  tiny.(4).(1) <- 1.;
  tiny.(3).(2) <- eta;
  check tiny;
  let overflow = bands 4 in
  overflow.(1).(1) <- Float.max_float;
  overflow.(4).(1) <- 2.;
  check overflow;
  let screen = bands 4 in
  screen.(4).(1) <- Float.max_float;
  screen.(5).(1) <- Float.max_float;
  check screen;
  let invalid = bands 4 in
  invalid.(0).(1) <- nan;
  invalid.(4).(1) <- infinity;
  check invalid;
  let seed = ref 0x74ad523cc1296L in
  let next () =
    seed :=
      Int64.add (Int64.mul !seed 6364136223846793005L) 1442695040888963407L;
    !seed
  in
  for case = 0 to 199 do
    let n = 3 + (case mod 67) in
    let xs =
      Array.init 6 (fun _ ->
          Array.init n (fun _ ->
              let word = next () in
              let sign = if Int64.logand word 1L = 0L then 1. else -1. in
              let mantissa =
                1.
                +. float
                     (Int64.to_int
                        (Int64.logand
                           (Int64.shift_right_logical word 1)
                           0xfffffL))
                   /. 1048576.
              in
              let exponent =
                Int64.to_int
                  (Int64.logand (Int64.shift_right_logical word 21) 2047L)
                - 1074
              in
              Float.ldexp (sign *. mantissa) exponent))
    in
    check xs
  done;
  let metrics = Array.make 2 0. and indices = Array.make 3 0 in
  List.iter
    (fun (first, last) ->
      rejects "native interval guard" (fun () ->
          raw ordinary first last metrics indices))
    [ (0, 1); (1, 514); (2, 1); (1, 257); (min_int, 1); (1, max_int) ];
  rejects "native band count" (fun () -> raw [||] 1 2 metrics indices);
  let bad = Array.copy ordinary in
  bad.(2) <- [||];
  rejects "native band length" (fun () -> raw bad 1 2 metrics indices);
  rejects "native metric shape" (fun () -> raw ordinary 1 2 [||] indices);
  rejects "native index shape" (fun () -> raw ordinary 1 2 metrics [||]);
  rejects "native array tag" (fun () ->
      wrong_tag (Array.make 6 [| 0; 1; 2 |]) 1 1 metrics indices);
  indices.(0) <- 2;
  rejects "native obstacle mode" (fun () -> raw ordinary 1 2 metrics indices);
  indices.(0) <- 0;
  indices.(1) <- 514;
  rejects "native worst-row state" (fun () -> raw ordinary 1 2 metrics indices);
  print_endline
    "American residual operation graph, chunks and safety controls passed"
