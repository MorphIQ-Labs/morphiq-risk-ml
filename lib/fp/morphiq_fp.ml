(* The library's binary64 multiplication, opened into every module of
   morphiq_risk (lib/dune: -open Morphiq_fp).

   OCaml's arm64, power, riscv and s390x backends contract a +. b *. c into
   one fused multiply-add, rounding once; amd64 rounds twice (OCaml 5.3,
   asmcomp/arm64/selection.ml). A product formed here is an unboxed,
   non-allocating call to a C function that returns RN(a b). It is not a
   multiplication node the backend can fuse with the next addition, and a
   single C multiply cannot be contracted, so every platform performs the
   roundings the source states. A fused multiply-add is written as
   Float.fma. *)

external ( *. ) : (float[@unboxed]) -> (float[@unboxed]) -> (float[@unboxed])
  = "morphiq_fp_mul_byte" "morphiq_fp_mul"
[@@noalloc]
