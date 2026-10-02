(* Deliberate IEEE witnesses, run in native and bytecode modes. They test the
   arithmetic trust boundary independently of financial reference fixtures. *)
let opaque = Sys.opaque_identity
let mul = Morphiq_fp.( *. )

let check label expected actual =
  if Int64.bits_of_float expected <> Int64.bits_of_float actual then
    failwith (Printf.sprintf "%s: expected %h, got %h" label expected actual)

let () =
  let a = opaque (1.0 +. 0x1p-27) and b = opaque (1.0 -. 0x1p-27) in
  check "separate multiplication" 1.0 (mul a b);
  check "multiplication is not implicitly contracted" 0.0 (mul a b -. 1.0);
  check "explicit fused residual" (-0x1p-54) (Float.fma a b (-1.0));
  check "even lower tie" 1.0 (opaque 1.0 +. opaque 0x1p-53);
  check "even upper tie" 0x1.0000000000002p+0
    (opaque 0x1.0000000000001p+0 +. opaque 0x1p-53);
  check "gradual product underflow" 0x1p-1023
    (mul (opaque Float.min_float) (opaque 0.5));
  check "subnormal input survives" 0x1p-1074
    (mul (opaque 0x1p-1074) (opaque 1.0));
  check "subnormal halfway rounds to even zero" 0.0
    (mul (opaque 0x1p-1074) (opaque 0.5));
  check "gradual division underflow" 0x1p-1023
    (opaque Float.min_float /. opaque 2.0);
  check "signed zero" (-0.0) (mul (opaque (-0.0)) (opaque 1.0));
  check "correctly rounded square root" 0x1.6a09e667f3bcdp+0
    (Float.sqrt (opaque 2.0));
  check "positive overflow remains visible" Float.infinity
    (mul (opaque Float.max_float) (opaque 2.0));
  if not (Float.is_nan (opaque 0.0 /. opaque 0.0)) then
    failwith "invalid arithmetic must remain NaN";
  (* Exercise the allocating bytecode wrapper across collections as well as
     the native unboxed entry point. The arithmetic result is exact. *)
  for i = 1 to 10_000 do
    check "foreign multiplication after allocation"
      (float (2 * i))
      (mul (opaque (float i)) (opaque 2.0));
    if i mod 100 = 0 then Gc.minor ()
  done;
  Printf.printf "IEEE arithmetic contract passed (%s, %d-bit runtime)\n"
    Sys.ocaml_version Sys.word_size
