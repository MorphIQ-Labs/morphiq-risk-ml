module BA = Bigarray.Array1

external solve :
  float array array ->
  bool array ->
  (float, Bigarray.float64_elt, Bigarray.c_layout) BA.t ->
  int = "morphiq_experiment_dgtsv"

external rounding : int -> int = "morphiq_experiment_rounding"
external flags : int -> int = "morphiq_experiment_flags"
external flush : int -> int = "morphiq_experiment_flush"

let check text ok = if not ok then failwith text
let scratch n = BA.create Bigarray.float64 Bigarray.c_layout (4 * n)

let bands n =
  Array.init 9 (fun k ->
      Array.init (n + 2) (fun _ ->
          if k = 1 || k = 6 then 2.
          else if k = 0 || k = 2 then -0.25
          else if k = 8 then 42.
          else 0.))

let bits a = Array.map Int64.bits_of_float a

let rejects text f =
  let yes =
    try
      ignore (f ());
      false
    with Invalid_argument _ -> true
  in
  check text yes

let simple () =
  let a = bands 3 in
  List.iteri (fun j b -> a.(7).(j + 1) <- b) [ 1.5; 3.; 5.5 ];
  a

let run () =
  let a = simple () in
  let mask = Array.make 5 false in
  let work = scratch 3 in
  Gc.full_major ();
  check "exact system status" (solve a mask work = 0);
  check "exact system vector" (Array.sub a.(8) 1 3 = [| 1.; 2.; 3. |]);
  Gc.full_major ();
  let saved = Array.map bits a in
  rejects "bad workspace" (fun () -> solve a mask (scratch 4));
  check "failure preserves arrays" (Array.map bits a = saved);
  rejects "writable alias" (fun () ->
      let b = Array.copy a in
      b.(7) <- b.(6);
      solve b mask work);
  rejects "bad mask shape" (fun () -> solve a [||] work);
  rejects "bad band shape" (fun () ->
      let b = Array.copy a in
      b.(0) <- [||];
      solve b mask work);
  let nonfinite = simple () in
  nonfinite.(7).(2) <- nan;
  check "nonfinite failure" (solve nonfinite mask work = 6);
  check "no partial output on nonfinite" (nonfinite.(8) = Array.make 5 42.);
  let singular = bands 3 in
  Array.fill singular.(6) 0 5 0.;
  Array.fill singular.(0) 0 5 0.;
  Array.fill singular.(2) 0 5 0.;
  check "singular INFO" (solve singular mask work = 5);
  check "no output on singular" (singular.(8) = Array.make 5 42.);
  let pivot = bands 2 in
  pivot.(6).(1) <- 0.;
  pivot.(6).(2) <- 1.;
  pivot.(0).(2) <- -1.;
  pivot.(2).(1) <- -1.;
  pivot.(7).(1) <- -2.;
  pivot.(7).(2) <- 1.;
  check "pivoted status" (solve pivot (Array.make 4 false) (scratch 2) = 0);
  check "pivoted exact vector" (Array.sub pivot.(8) 1 2 = [| 1.; 2. |]);
  let identity = bands 3 in
  identity.(6).(2) <- 1.;
  List.iteri (fun j v -> identity.(7).(j + 1) <- v) [ -0.5; 10.; 3.5 ];
  let mask = [| false; false; true; false; false |] in
  check "identity status" (solve identity mask work = 0);
  check "identity couplings" (Array.sub identity.(8) 1 3 = [| 1.; 10.; 3. |]);
  check "nearest entry" (rounding (-1) = 0);
  ignore (rounding 1);
  Fun.protect
    ~finally:(fun () -> ignore (rounding 0))
    (fun () ->
      rejects "unsupported round mode" (fun () ->
          solve (simple ()) (Array.make 5 false) work);
      check "unsupported caller mode preserved" (rounding (-1) = 1));
  check "valid caller mode preserved"
    (solve (simple ()) (Array.make 5 false) work = 0 && rounding (-1) = 0);
  let single = bands 1 in
  single.(6).(1) <- 1.;
  single.(7).(1) <- Int64.float_of_bits 1L;
  check "gradual subnormal"
    (solve single (Array.make 3 false) (scratch 1) = 0
    && Int64.bits_of_float single.(8).(1) = 1L);
  single.(7).(1) <- -0.;
  check "signed zero"
    (solve single (Array.make 3 false) (scratch 1) = 0
    && Int64.bits_of_float single.(8).(1) = Int64.min_int);
  single.(6).(1) <- Float.min_float;
  single.(7).(1) <- Float.max_float;
  let work1 = scratch 1 and mask1 = Array.make 3 false in
  let saved_flags = flags (-1) in
  ignore (flags 0);
  Fun.protect
    ~finally:(fun () ->
      ignore (flags 0);
      ignore (flags saved_flags))
    (fun () ->
      check "finite input overflow refused" (solve single mask1 work1 = 6);
      check "floating flags restored on failure" (flags (-1) = 0));
  let old_flush = flush (-1) in
  ignore (flush 1);
  Fun.protect
    ~finally:(fun () -> ignore (flush old_flush))
    (fun () ->
      rejects "flush-to-zero environment" (fun () ->
          solve (simple ()) (Array.make 5 false) work);
      check "unsupported flush preserved" (flush (-1) = 1));
  let domains =
    Array.init 4 (fun _ ->
        Domain.spawn (fun () ->
            for _ = 1 to 100 do
              let a = simple () in
              check "concurrent solve"
                (solve a (Array.make 5 false) (scratch 3) = 0
                && Array.sub a.(8) 1 3 = [| 1.; 2.; 3. |])
            done))
  in
  Array.iter Domain.join domains;
  print_endline
    "DGTSV: \
     exact/identity/pivot/singular/nonfinite/shape/alias/GC/environment/concurrent-owner \
     controls pass"

let () = run ()
