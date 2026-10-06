open Morphiq_risk
module K = Internal.American_policy
module R = American_policy_reference

let expect label ok = if not ok then failwith label
let bits a = Array.map (Array.map Int64.bits_of_float) a

external raw :
  float array array -> bool array array -> int array -> int -> int -> int
  = "morphiq_american_policy"

external wrong_tag :
  int array array -> bool array array -> int array -> int -> int -> int
  = "morphiq_american_policy"

let bands n =
  Array.init 9 (fun k ->
      Array.init n (fun i ->
          match k with
          | 0 | 2 -> -0.25
          | 1 | 6 -> 2.
          | 3 | 7 -> float (i mod 13)
          | 4 -> float (i mod 17)
          | 5 -> float (i mod 7)
          | _ -> 0.))

let flags n = [| Array.init n (fun i -> i mod 3 = 0); Array.make n false |]
let statuses = Array.make 7 false

let compare_phase original original_flags phase obstacle chunk fingerprint =
  let a = Array.map Array.copy original and b = Array.map Array.copy original in
  let fa = Array.map Array.copy original_flags
  and fb = Array.map Array.copy original_flags in
  let sa = [| phase; obstacle; 0; fingerprint; 0 |]
  and sb = [| phase; obstacle; 0; fingerprint; 0 |] in
  let n = Array.length a.(0) in
  let i = ref (if phase = 2 then n - 2 else if phase = 1 then 2 else 1) in
  let status = ref 0 in
  while !status = 0 && if phase = 2 then !i >= 1 else !i <= n - 2 do
    let last =
      if phase = 2 then max 1 (!i - chunk + 1) else min (n - 2) (!i + chunk - 1)
    in
    let expected = R.run a fa sa ~first:!i ~last in
    Gc.minor ();
    let actual = raw b fb sb !i last in
    expect "native phase status" (expected = actual);
    expect "native partial float state" (bits a = bits b);
    expect "native policy mask and old mask" (fa = fb);
    expect "native accounting/fingerprint" (sa = sb);
    statuses.(actual) <- true;
    status := actual;
    i := if phase = 2 then last - 1 else last + 1
  done

let check original =
  let n = Array.length original.(0) in
  List.iter
    (fun chunk ->
      List.iter
        (fun obstacle ->
          List.iter
            (fun phase ->
              List.iter
                (compare_phase original (flags n) phase obstacle chunk)
                [ 17; max_int; min_int ])
            [ 0; 1; 2; 3 ])
        [ 0; 1 ])
    [ 1; 7; 255; 256 ]

let rejects label f =
  let rejected =
    try
      ignore (f ());
      false
    with Invalid_argument _ -> true
  in
  expect label rejected

let wrapper a f =
  K.create ~lo:a.(0) ~diag:a.(1) ~hi:a.(2) ~rhs:a.(3) ~values:a.(4)
    ~payoff:a.(5) ~pivots:a.(6) ~solution_rhs:a.(7) ~candidate:a.(8) ~mask:f.(0)
    ~oldmask:f.(1)

let exact_system () =
  let a = bands 5 and f = [| Array.make 5 false; Array.make 5 false |] in
  a.(3).(1) <- 1.5;
  a.(3).(2) <- 3.;
  a.(3).(3) <- 5.5;
  let state = wrapper a f in
  K.reset state ~obstacle:false;
  expect "selection succeeds" (K.run state K.Select ~first:1 ~last:3 = 0);
  expect "elimination succeeds" (K.run state K.Eliminate ~first:2 ~last:3 = 0);
  expect "substitution succeeds" (K.run state K.Substitute ~first:3 ~last:1 = 0);
  expect "copy succeeds" (K.run state K.Copy ~first:1 ~last:3 = 0);
  (* Independent exact-rational original-system residual; exact solution 1,2,3.
     Strict dominance margin >= 3/2 turns residual/margin into a discrete
     infinity-norm bound. This is not a continuum price certificate. *)
  let q = Q.of_float and tolerance = Q.of_float 0x1p-44 in
  for i = 1 to 3 do
    let x = q a.(4).(i) in
    let previous = if i = 1 then Q.zero else q a.(4).(i - 1) in
    let next = if i = 3 then Q.zero else q a.(4).(i + 1) in
    let residual =
      Q.sub
        (Q.sub
           (Q.mul (Q.of_int 2) x)
           (Q.mul (Q.make Z.one (Z.of_int 4)) (Q.add previous next)))
        (q a.(3).(i))
    in
    expect "exact discrete residual" (Q.compare (Q.abs residual) tolerance <= 0);
    expect "exact discrete solution"
      (Q.compare (Q.abs (Q.sub x (Q.of_int i))) tolerance <= 0)
  done;
  bits a

let independent_controls () =
  (* (1+2^-27)(1-2^-27)-1 = -2^-54 exactly. A fused
     policy decision distinguishes it from a rounded product, which is zero. *)
  let a = bands 5 and f = [| Array.make 5 false; Array.make 5 false |] in
  a.(0).(2) <- 0.;
  a.(1).(2) <- 0.;
  a.(2).(2) <- 1. +. 0x1p-27;
  a.(4).(3) <- 1. -. 0x1p-27;
  a.(3).(2) <- 1.;
  a.(4).(2) <- 0.;
  a.(5).(2) <- 0x1p-55;
  let state = [| 0; 1; 0; 17; 0 |] in
  expect "fused exact sign" (raw a f state 2 2 = 0 && not f.(0).(2));
  a.(0).(2) <- 1. +. 0x1p-27;
  a.(6).(1) <- 1.;
  a.(2).(1) <- 1. -. 0x1p-27;
  a.(6).(2) <- 1.;
  state.(0) <- 1;
  expect "separately rounded exact pivot"
    (raw a f state 2 2 = 0 && a.(6).(2) = 0.);
  (* Independent system with an identity obstacle row: solution (1,10,3).
     Its neighbours must retain coupling to that row, while the identity row
     has neither a lower nor an upper coefficient. *)
  let a = bands 5 and f = [| Array.make 5 false; Array.make 5 false |] in
  f.(0).(2) <- true;
  a.(6).(2) <- 1.;
  a.(7).(1) <- -0.5;
  a.(7).(2) <- 10.;
  a.(7).(3) <- 3.5;
  let k = wrapper a f in
  expect "mixed identity elimination" (K.run k K.Eliminate ~first:2 ~last:3 = 0);
  expect "mixed identity substitution"
    (K.run k K.Substitute ~first:3 ~last:1 = 0);
  List.iteri
    (fun i x -> expect "independent identity solution" (a.(8).(i + 1) = x))
    [ 1.; 10.; 3. ];
  List.iter
    (fun (phase, band, row, x, code) ->
      let a = bands 5 and f = [| Array.make 5 false; Array.make 5 false |] in
      a.(band).(row) <- x;
      let state = [| phase; 0; 0; 17; 0 |] in
      let first = if phase = 1 then 2 else 3 in
      expect "explicit failure outcome" (raw a f state first first = code);
      expect "failure consumes one row" (state.(4) = 1))
    [ (1, 6, 1, 0., 2); (2, 6, 3, 0., 5); (1, 7, 2, infinity, 4) ]

let () =
  independent_controls ();
  check (bands 3);
  check (bands 514);
  let fused = bands 5 in
  fused.(0).(2) <- 0.;
  fused.(1).(2) <- 0.;
  fused.(2).(2) <- 1. +. 0x1p-27;
  fused.(4).(3) <- 1. -. 0x1p-27;
  fused.(3).(2) <- 1.;
  check fused;
  let unfused = bands 5 in
  unfused.(0).(2) <- 1. +. 0x1p-27;
  unfused.(6).(1) <- 1.;
  unfused.(2).(1) <- 1. -. 0x1p-27;
  unfused.(6).(2) <- 1.;
  check unfused;
  let tiny = bands 9 in
  tiny.(4).(1) <- -0.;
  tiny.(8).(3) <- -0.;
  tiny.(3).(2) <- Float.next_after 0. infinity;
  tiny.(0).(4) <- Float.next_after 0. infinity;
  check tiny;
  List.iter
    (fun (band, row, value) ->
      let a = bands 9 in
      a.(band).(row) <- value;
      check a)
    [
      (1, 2, infinity);
      (0, 2, nan);
      (6, 1, 0.);
      (6, 4, -1.);
      (6, 2, infinity);
      (7, 2, infinity);
      (7, 3, Float.max_float);
      (6, 3, Float.next_after 0. infinity);
    ];
  expect "all six finite/pivot failures exercised"
    (Array.for_all Fun.id statuses);
  let a = bands 514 and f = flags 514 and s = [| 0; 0; 0; 17; 0 |] in
  List.iter
    (fun (first, last) -> rejects "bad range" (fun () -> raw a f s first last))
    [ (0, 1); (1, 513); (3, 2); (1, 257); (min_int, max_int) ];
  List.iter
    (fun phase ->
      let state = Array.copy s in
      state.(0) <- phase;
      rejects "bad phase" (fun () -> raw a f state 1 1))
    [ -1; 4 ];
  rejects "bad band count" (fun () -> raw [||] f s 1 1);
  rejects "bad flag count" (fun () -> raw a [||] s 1 1);
  rejects "bad state count" (fun () -> raw a f [||] 1 1);
  rejects "bad state value" (fun () -> raw a f [| 0; 2; 0; 17; 0 |] 1 1);
  let bad = Array.copy a in
  bad.(2) <- [| 0. |];
  rejects "bad band length" (fun () -> raw bad f s 1 1);
  let alias = Array.copy a in
  alias.(7) <- alias.(3);
  rejects "native write alias" (fun () -> raw alias f s 1 1);
  rejects "owner write alias" (fun () -> wrapper alias f);
  rejects "flag alias" (fun () -> raw a [| f.(0); f.(0) |] s 1 1);
  rejects "wrong float tag" (fun () ->
      wrong_tag
        (Array.make 9 [| 0; 0; 0 |])
        [| Array.make 3 false; Array.make 3 false |]
        s 1 1);
  rejects "bad elimination first" (fun () -> raw a f [| 1; 0; 0; 17; 0 |] 1 1);
  rejects "bad descending range" (fun () -> raw a f [| 2; 0; 0; 17; 0 |] 1 2);
  Gc.full_major ();
  let expected = exact_system () in
  let d = Domain.spawn exact_system in
  expect "independent concurrent owner"
    (exact_system () = expected && Domain.join d = expected);
  (* No rounding-mode/subnormal/signed-zero change across foreign execution. *)
  expect "round to nearest remains"
    (Sys.opaque_identity 1. +. Sys.opaque_identity 0x1p-53 = 1.);
  expect "gradual underflow remains"
    (Sys.opaque_identity Float.min_float /. Sys.opaque_identity 2. > 0.);
  expect "signed zero remains"
    (Int64.bits_of_float (-.Sys.opaque_identity 0.) = Int64.min_int);
  print_endline
    "native policy: operation graphs, partial failures, exact systems, \
     shape/alias controls and independent owners pass"
