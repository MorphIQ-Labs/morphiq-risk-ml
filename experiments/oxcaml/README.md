# OxCaml worker-isolation experiment — decision for #22

**Retain the checked-worker experiment; defer production compiler adoption.**
The production planner remains upstream OCaml 5.3.0 Flambda with -O3. Compile-time
worker isolation is demonstrated through the actual four-model pricing path,
not just a dummy portable wrapper. The complete planner/coordinator is not yet
mode checked, and this experiment does not certify every foreign/runtime path.

## Recorded environments

All experiments use source `f05ec395f3fcaf3f12429c3f9dbbbae7655acf63` on macOS
ARM64 (Apple M1 Pro). [Provenance](../../docs/evidence/planner-experiment-provenance.json)
retains compiler/source commits, installed packages and artifact checksums.
Full opam exports with package definitions/checksums/patches are retained as
`ox52.export.gz` and `ox54.export.gz`; they are dependency manifests, not compiled
binaries. The OxCaml repository is pinned to
`f1bd228dda31430bf6271f0f9adb2e604c6957ca`.

| Environment | Compiler source | Canonical parallel library |
| --- | --- | --- |
| Upstream baseline | OCaml 5.3.0 Flambda, existing locked switch | Existing Domain-based planner |
| OxCaml 5.4.0-ox7 | `16927fa9eaa8f8b7e09263ac99019f25f89817a1` | Dependency solver rejects the pinned package graph |
| OxCaml 5.2.0minus39 | `2515546fea38e21e8143cc41db663bd56efc8d06` | `parallel.v0.18~preview.130.106+341`, installed and executed |

The website's older scheduler tutorial no longer matches the selected package's
API. The pinned canonical source provides `Parallel_scheduler.with_parallel`
from `parallel.scheduler`; that API, read from the installed interface, is used
in the successful test. The 5.4 test separately uses `Domain.Safe.spawn`.
The [solver diagnostic](../../docs/evidence/planner-ox54-parallel-solver.txt) is retained.
No claim is made that `parallel` installed on 5.4. The 5.2 experiment bypasses
package installation of this project and builds its copied source with Dune;
it does **not** lower the project's declared OCaml >= 5.3 requirement.

## What the compiler actually checked

First, unchanged upstream sources built under the experimental compilers.
They preserve tested results but emit explicit warnings that ordinary
`Domain.spawn` is not the mode-checked boundary. That is useful conformance
evidence, not evidence of compiler-enforced race freedom.

Adding portable signatures initially failed for real pricing dependencies:
`Elementary` coefficient arrays, `Dd` reciprocal/factorial tables, and
`Normalised_black` threshold/function tables were ordinary mutable arrays.
Read-only usage discipline alone does not satisfy the compiler. The isolated
[patch](portable-numerics.patch) changes these private tables to immutable arrays
and adds checked portable signatures throughout the called numerical modules.
Constant bits and arithmetic operation order remain unchanged. Initializer
scratch is local and is copied into immutable storage before sharing.

The positive worker uses immutable scalar request records/lists, creates scratch
inside each worker, and calls Production admission and certified prices for
BSM, Black-76, displaced Black and Bachelier. The canonical 5.2 fork/join path
returns 32 certified prices equal to sequential results. The 5.4 Safe.spawn path
returns 16 equal prices. The positive worker template is `worker.ml.in` so the
upstream formatter does not attempt to parse experimental syntax.

Four negative programs on **both** compilers are rejected for the intended
contention/portability violation, not a syntax error:

- captured mutable global state;
- an unsynchronized shared hash-table cache;
- reading a mutable shared snapshot;
- aliased scratch captured across the worker boundary.

Each has a repaired positive control that compiles. Full diagnostics and exact
source snippets are retained in [5.2 controls](../../docs/evidence/planner-ox52-mode-controls.json)
and [5.4 controls](../../docs/evidence/planner-ox54-mode-controls.json).

The trust boundary includes the compiler/runtime, canonical scheduler and its
synchronization, standard-library primitives, and the small C multiplication
primitive. Its portable external declaration is a reviewed trust assertion:
the compiler does not inspect C for races or prove IEEE semantics. The C body
has no shared mutable state. No unsafe cast, Obj escape hatch or diagnostic
suppression is used to force the worker to compile. The rest of the upstream
planner still uses frozen private arrays and coordinator-owned mutation under
an ownership contract; it is not covered by the prototype's mode proof.

## Numerical conformance

[5.2 conformance](../../docs/evidence/planner-ox52-conformance.json) and
[5.4 conformance](../../docs/evidence/planner-ox54-conformance.json) retain the
actual command outputs for the checked worker, scalar determinism digest,
model consistency, production acceptance boundaries, IV termination controls
and all 8,330 batch IV fixture comparisons. Every command passes. The scalar
digest is identical to the upstream baseline.

Independent Arb checks all 2,376 planner price/Greek certificates in the
[5.4 unchanged](../../docs/evidence/planner-ox54-arb-reference.json),
[5.4 portable](../../docs/evidence/planner-ox54-portable-arb-reference.json), and
[5.2 portable](../../docs/evidence/planner-ox52-portable-arb-reference.json)
builds. All output hashes equal the upstream campaign, including error radii;
worker counts 1–4 agree. No served-bit or outcome change was found in these
checks. This is a specified conformance subset, not a claim that every ordinary
suite/tool runs unchanged under OxCaml. In particular, the analytical source
extractor currently recognizes mutable-array literal syntax and rejects the
immutable-array spelling ([retained diagnostic](../../docs/evidence/planner-ox-source-parser-limitation.txt)). Production adoption requires updating that parser
without weakening its numerical checks and refreshing transitive provenance.

## Performance scope and decision

[The 95-run comparison](../../docs/evidence/planner-compiler-comparison.json)
separates compiler changes from the immutable-table/signature patch. It includes
scalar, typed batch and packed-layout runs, 1/4-worker planner jobs, allocation,
GC, peak RSS and ten small-job latency repetitions per environment. Alternate
rounds reverse compiler order. All aggregate output digests agree. No other
local build/test ran during this comparison; the host remains a shared
workstation, and recorded load/variation limit generalization.

Median execution seconds for 256 instruments × three scenarios:

| Environment | 1 worker | 4 workers |
| --- | ---: | ---: |
| Upstream 5.3 | 0.9223 | 0.2709 |
| Ox 5.4, unchanged | 0.7767 | 0.2253 |
| Ox 5.4, portable numerics | 0.7828 | 0.2247 |
| Ox 5.2, unchanged | 0.7777 | 0.2302 |
| Ox 5.2, portable numerics | 0.7834 | 0.2298 |

For 32 instruments × three scenarios with four workers, the upstream median
was 45.55 ms (range 44.81–46.77 ms). Ox 5.4 portable was 39.75 ms
(38.82–41.37 ms), and Ox 5.2 portable was 41.65 ms (40.72–42.53 ms).
Ten observations describe this small sample; they do not establish a production
p99 or deadline. These timing jobs use the existing Domain-based planner compiled
by each toolchain. They are **not** a benchmark of the canonical mode-checked
scheduler prototype. Hardware counters were not collected.

This modest host-specific compiler improvement does not clear adoption:

1. The complete planner snapshot/scheduler/sink boundary needs a mode-aware
   representation and API review; the checked pricing worker is narrower.
2. The newer compiler's canonical parallel dependency graph does not solve;
   the working older toolchain is below the production package's minimum.
3. The source-analysis/provenance tooling needs reviewed immutable-array support.
4. OxCaml project conformance was executed on ARM64 only. The vendor documents
   x86-64 and ARM64 support; that does not establish this project's x86-64
   conformance. Unsupported platforms/extensions and future library/compiler
   compatibility remain deployment obligations.

The experiment therefore delivers a **defer** decision with a working checked
prototype and reproducible evidence. No compiler dependency, required CI lane,
production arithmetic, or public planner execution policy is migrated.
Rollback is simply use of the unchanged upstream integration branch; the
experiment has no runtime dependency in the package.

## Reproduction

The [pre-scoring protocol](hypothesis.md) records the hypotheses and pins.
Create a separate opam root, register the pinned OxCaml repository, and install
the exact compiler and parallel versions above (or import the decompressed full
switch export). Do not import them over the production switch.

```sh
python3 experiments/oxcaml/prepare.py --source f05ec395f3fcaf3f12429c3f9dbbbae7655acf63 \
  --destination /tmp/planner-ox52-reproduction --portable --canonical-parallel
# From that external tree, with the isolated Ox 5.2 switch selected:
dune build @install bench/ox_worker.exe bench/planner_reference.exe
dune exec bench/ox_worker.exe
```

For 5.4, omit `--canonical-parallel`. Omit `--portable` for unchanged-source
comparisons. `check_modes.py --ocamlc /path/to/ox/ocamlc --output /tmp/modes.json`
compiles the eight positive/negative controls. `scripts/audit_planner.py` runs
the independent campaign with the existing pinned optional oracle environment.
`compare.py --help` documents the manual comparison; it is not in default CI.

Primary basis: [OxCaml fork/join tutorial](https://oxcaml.org/documentation/tutorials/intro-to-parallelism-part-1/),
[immutable arrays](https://oxcaml.org/documentation/miscellaneous-extensions/immutable-arrays/),
[installation/platform limits](https://oxcaml.org/get-oxcaml/), and the exact
installed compiler/parallel interfaces identified by the retained manifests.
