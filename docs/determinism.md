# Determinism

The library is designed to serve the same bits for the same inputs on every platform.

- **No platform libm.** `exp`, `expm1`, `log`, `log1p` and `cbrt` are this project's own (`Internal.Elementary`). They are built from IEEE-754 basic operations and fma, which are correctly rounded on every conforming platform. Each is within 1 ULP of the correctly rounded value, measured over 111k mpmath references (`oracle/gen_elementary.py`, `test/oracle_elementary.ml`). The system libm can differ by an ULP or more between macOS, glibc and musl, and those differences would otherwise reach served prices.
- **No contraction.** OCaml's arm64, power, riscv and s390x backends contract `a +. b *. c` into one fused multiply-add, rounding once, while amd64 rounds twice (OCaml 5.3 `asmcomp/arm64/selection.ml`; upstream keeps this behaviour). An earlier version of this document said OCaml never contracts. That was wrong: the library's arm64 builds contained about 500 fused instructions, and Linux x86-64 served different bits. Now:
  - every multiplication in `lib/` is `Morphiq_fp.( *. )` (opened with `-open Morphiq_fp`), an unboxed, non-allocating call to a C function that returns RN(a·b). It is not a multiplication node the backend can fuse, and a lone C multiply cannot be contracted;
  - every fused multiply-add is an explicit `Float.fma`, correctly rounded everywhere: this project's Horner helpers (including the generated error functions) and exact remainders. The retained Jäckel rational evaluations remain unfused; inverse-normal tail residuals use an explicit FMA;
  - the compiled library contains no `fmadd`, `fmsub`, `fnmadd` or `fnmsub` on arm64.
- **`sqrt` is IEEE.** It is correctly rounded by specification.
- **A digest checks it.** `test/determinism.ml` serves every quantity over a fixed corpus: price, implied volatility and the ten Greeks for BSM, displaced Black and Bachelier, 18,000+ contracts. It hashes the bit patterns with BLAKE2b-256 and compares the result with `test/determinism.digest`. CI runs it on Linux x86-64, Linux arm64 and macOS arm64.

The digest was recorded on macOS arm64 (Apple M1 Pro), OCaml 5.3.0 + flambda, after the contraction fix. Before it, Linux x86-64 served a different digest. A change to any served value changes the digest, so an intentional numerical change updates `test/determinism.digest` in the same PR, with the evidence `docs/stability.md` requires.

`test/fp_contract.ml` separately probes ties-to-even, gradual underflow,
signed zero, explicit fused versus separate arithmetic, square root and
nonfinite values. It exercises the multiplication boundary in native and
bytecode modes, including allocation/collection around the bytecode wrapper.
These small exact witnesses detect arithmetic-environment violations; they
do not prove a whole compiler or replace price/Greek/IV reference checks.
Candidate compiler/backends follow the
[numerical execution contract](numerical-backend-contract.md).

The [error-function qualification](results-error-functions.md) records the
intentional CALERF-replacement digest change, including fixture accuracy,
per-row refinement and a separate public-replay comparison. Replay IV values
use each implementation's served quote; fixed-quote IV accuracy is tested
separately by the independent IV corpus.

The normal oracle also hashes all 11,379 inverse outputs in fixture order to
`test/inverse_normal.digest`. Its separate replay gate covers the inverse
primitive directly; the financial replay corpus/digest remains unchanged by
the AS241 replacement. Mutation guards omit this replay comparison and retain
the numerical and monotonicity witnesses.

The #80 Greek cancellation change updates the public digest to
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
All 1,013 changed replay words are zero-volatility theta; original-input Arb
references put each new value within 1 ULP. Other fields and outcome classes
are unchanged in that replay. See the [qualification](results-greek-cancellation.md).
