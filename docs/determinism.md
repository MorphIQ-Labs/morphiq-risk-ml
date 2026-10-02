# Determinism

The library is designed to serve the same bits for the same inputs on every platform.

- **No platform libm.** `exp`, `expm1`, `log`, `log1p` and `cbrt` are this project's own (`Internal.Elementary`). They are built from IEEE-754 basic operations and fma, which are correctly rounded on every conforming platform. Each is within 1 ULP of the correctly rounded value, measured over 111k mpmath references (`oracle/gen_elementary.py`, `test/oracle_elementary.ml`). The system libm can differ by an ULP or more between macOS, glibc and musl, and those differences would otherwise reach served prices.
- **No contraction.** OCaml's arm64, power, riscv and s390x backends contract `a +. b *. c` into one fused multiply-add, rounding once, while amd64 rounds twice (OCaml 5.3 `asmcomp/arm64/selection.ml`; upstream keeps this behaviour). An earlier version of this document said OCaml never contracts. That was wrong: the library's arm64 builds contained about 500 fused instructions, and Linux x86-64 served different bits. Now:
  - every multiplication in `lib/` is `Morphiq_fp.( *. )` (opened with `-open Morphiq_fp`), an unboxed, non-allocating call to a C function that returns RN(a·b). It is not a multiplication node the backend can fuse, and a lone C multiply cannot be contracted;
  - every fused multiply-add is an explicit `Float.fma`, correctly rounded everywhere: this project's Horner helper (`Elementary.horner`) and the exact remainders. The reference algorithms (Cody, AS241, Jäckel) evaluate unfused, as their references do on baseline x86-64;
  - the compiled library contains no `fmadd`, `fmsub`, `fnmadd` or `fnmsub` on arm64.
- **`sqrt` is IEEE.** It is correctly rounded by specification.
- **A digest checks it.** `test/determinism.ml` serves every quantity over a fixed corpus: price, implied volatility and the ten Greeks for BSM, displaced Black and Bachelier, 18,000+ contracts. It hashes the bit patterns with BLAKE2b-256 and compares the result with `test/determinism.digest`. CI runs it on Linux x86-64, Linux arm64 and macOS arm64.

The digest was recorded on macOS arm64 (Apple M1 Pro), OCaml 5.3.0 + flambda, after the contraction fix. Before it, Linux x86-64 served a different digest. A change to any served value changes the digest, so an intentional numerical change updates `test/determinism.digest` in the same PR, with the evidence `docs/stability.md` requires.
