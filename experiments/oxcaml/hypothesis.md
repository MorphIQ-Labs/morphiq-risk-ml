# OxCaml experiment protocol (#22)

This protocol is fixed before comparison. The upstream baseline remains OCaml
5.3.0 Flambda, -O3. No compiler migration is authorized by a successful benchmark.
The correctness hypothesis is that the selected compiler rejects captured mutable
snapshots, caches, globals and aliased worker scratch at a portable worker
boundary, while accepting immutable inputs and private scratch. A portable
wrapper alone is insufficient: the called pricing path must be checked or its
unchecked boundary explicitly recorded as an adoption blocker.

The unchanged-source comparison must preserve scalar classifications, served
bits, certificates and the planner's scenario/aggregate semantics. Numerical
changes require separate analysis; benchmark speed cannot accept them. Compare
identical inputs/workers, repeated end-to-end latency, allocation/GC and RSS.
Do not introduce SIMD, local-allocation rewrites or new formulas in this study.
There is no arbitrary percentage threshold: portability, maintained dependency
support, checked boundaries and numerical conformance are required first.

Pinned compiler: `oxcaml-compiler.5.4.0-ox7`, upstream commit
`16927fa9eaa8f8b7e09263ac99019f25f89817a1`.
Pinned OxCaml opam repository: `f1bd228dda31430bf6271f0f9adb2e604c6957ca`.
Canonical `parallel` package selected from that repository:
`v0.18~preview.130.106+341`.

Installation uses a distinct opam root and switch, never the project switch.
Any source annotations or immutable coefficient representation experiment must
use a separate copied source tree and retain its exact patch. Default CI must
not build this experimental compiler or install its dependencies.

The host is macOS ARM64. x86-64 support must be distinguished between upstream
advertised support and actually executed project conformance. Unsupported hosts,
extensions, library constraints, diagnostic changes and untested cases must be
reported. The adoption decision may be defer/reject if a requirement fails; it
must not be described as successful whole-engine race-freedom certification.

Primary sources: https://oxcaml.org/get-oxcaml/ and
https://oxcaml.org/documentation/tutorials/intro-to-parallelism-part-1/.

The 5.4 toolchain's canonical `parallel` dependency solve fails against the
pinned repository. This is a dependency compatibility result, not a numerical
failure. The follow-up uses the documented 5.2 toolchain:
`oxcaml-compiler.5.2.0minus39`, commit
`2515546fea38e21e8143cc41db663bd56efc8d06`, with the same pinned `parallel` package.
The 5.4 capability test uses the compiler's checked `Domain.Safe.spawn` boundary;
it must not be mislabeled a successful `parallel` installation.
