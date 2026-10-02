# Determinism

The library is designed to serve the same bits for the same inputs on every platform.

- **No platform libm.** `exp`, `expm1`, `log`, `log1p` and `cbrt` are this project's own (`Internal.Elementary`). They are built from IEEE-754 basic operations and fma, which are correctly rounded on every conforming platform. Each is within 1 ULP of the correctly rounded value, measured over 111k mpmath references (`oracle/gen_elementary.py`, `test/oracle_elementary.ml`). The system libm can differ by an ULP or more between macOS, glibc and musl, and those differences would otherwise reach served prices.
- **No contraction.** OCaml does not fuse `a *. b +. c` into an fma. Every fma in the library is an explicit `Float.fma`, which is correctly rounded everywhere (in software where the hardware lacks it).
- **`sqrt` is IEEE.** It is correctly rounded by specification.
- **A digest checks it.** `test/determinism.ml` serves every quantity over a fixed corpus: price, implied volatility and the ten Greeks for BSM, displaced Black and Bachelier, 18,000+ contracts. It hashes the bit patterns with BLAKE2b-256 and compares the result with `test/determinism.digest`. CI runs it on Linux x86-64, Linux arm64 and macOS arm64.

The digest was recorded on macOS arm64 (Apple M1 Pro), OCaml 5.3.0 + flambda. A change to any served value changes the digest, so an intentional numerical change updates `test/determinism.digest` in the same PR, with the evidence `docs/stability.md` requires.
