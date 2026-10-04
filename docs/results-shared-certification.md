# Shared certification preparation: qualification and measurements

Issue [#8](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/8), 2026-10-04.
This is an additive multi-output API and internal planner optimization. The
[contract](shared-certification.md) defines dependencies, failure precedence,
call-local ownership and units. No numerical algorithm, reference, tolerance,
compiler flag or arithmetic operation order changes. No release is implied.

## Selection and scope

The initial ordinary BSM profile attributed 2,178,393 allocated bytes to each
original-model preparation, versus 18,717,885 bytes for eleven enclosures using
an already prepared model. Planner previously prepared the model eleven times
for those eleven requested outputs. The new call prepares it once. Its fixed
model/input group also needs admission only once. Enclosure evaluation, final
radius and acceptance remain separate for every requested output. Quantity-specific
CDF/Greek intermediates remain a possible future profiling target, with their
own dependency and failure analysis; they are not hoisted here.

The [diagnostic profile](evidence/shared-certification/preparation-profile.txt)
and [host record](evidence/shared-certification/preparation-host.json) precede
implementation. Its wall-clock samples are diagnostic, not the paired performance
claim. Preparation's immutable result or arithmetic failure is memoized only
inside one synchronous invocation; there is no plan-level or cross-worker cache.

## Correctness and compatibility

The [full ordinary suite](evidence/shared-certification/ordinary.log.gz) and
[final changed-test validation](evidence/shared-certification/final-ordinary.log.gz)
pass with build/install and formatting. The new native/bytecode guard covers
all four models, both sides, exact expiry, zero volatility, displaced low words,
invalid/admission/accuracy/arithmetic failures, duplicate and empty requests,
later successes after failures, distinct volatilities and concurrent calls on
one admission. Negative compilation witnesses reject mixed coordinates and
untyped Theta limits. Original independent references check 4,176 public
certificates; each is also checked through the multi-output API at broad,
exact-certificate and (where positive) immediately smaller accuracy limits.

The [independent Arb planner audit](evidence/shared-certification/planner-arb.json)
contains all 2,376 certificates over 27 scenarios, eight instruments and four
models. Original-input price and formal-series Greek references contain every
served result, with corrupt-certificate and truncated-output rejection controls.
Workers 1/2/3/4 emit identical bytes. The
[before/after replay](evidence/shared-certification/planner-replay.json) also matches
main exactly: SHA-256 `f3f24cbb32e0a6c151ab34038b6adb5428700cc0c9a14d814f1f11e049610fd6`.
The ordinary public digest remains
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
Identity checks establish compatibility; the independent references establish
accuracy over their exercised inputs, not a universal proof.

All [six affected mutation witnesses](evidence/shared-certification/mutations.log.gz)
pass after a clean mutation-profile baseline: per-output limits, scalar accuracy,
certificate radius, post-expiry exclusion, aggregate scalar radius and incomplete
totals. Each mutant builds and is rejected by its designated numerical/precondition
guard. The new `multi-output-limit` witness checks explicit limit failures before
running equivalence assertions. The full optional catalog grows to 85; default
CI remains seven reviewed mutants. This local run does not claim the full 85.

The [immutable installed source rehearsal](evidence/shared-certification/installed-40870cb.json)
compiles an external consumer in native and bytecode against the installed public
package, including four-model multi-output prices, Delta and typed Theta.
All ten installed notices match. The existing full 649-case Exchange replay is
unchanged in both modes: 625 served, 10 numerical failures, five accuracy failures,
seven invalid inputs and two invalid-accuracy controls. Source archive, installation
report and build log are retained in the local acceptance archive under the source
commit. This is local package evidence, separate from the previous candidate's
three-platform/full-84 qualification and from institutional acceptance.

## Paired measurement

Baseline library: `d9967018b219f8b68c0e485e5a78a7973a101a1c`.
Candidate implementation/harness: `40870cb5ab34907ab998bbaf5078f5a007bada42`.
Only identical benchmark scaffolding is copied into the baseline worktree; its
library is unchanged. The [raw campaign](evidence/shared-certification/portfolio-abba.json.gz)
retains source, binary and driver hashes, compiler configuration, per-process
host loads, complete ordered-outcome digests, counts and every timing/allocation
sample. The subsequent rebase onto documentation-only closeout `3f3ef51134923aed1235b752da148bfb16ca04fe`
changes no implementation, tests, benchmark or measurement driver from that source.
The equivalent rebased implementation is `fe469070475cf346585e01c8bf678b09d28db0a5`; use this public PR commit
for reproduction and verify its source files against the recorded hashes. The
pre-rebase measurement/install commit is retained locally with its source archive.

Apple M1 Pro, macOS 27 arm64; OCaml 5.3.0 Flambda, Dune release, library `-O3`,
standard release flags for the benchmark. All task-owned builds, tests, mutations
and package replays finished before timing. Other host work continued: sampled
one-minute load ranged 21.67–36.17. These are shared-host observations, not an
isolated latency guarantee. Large candidate timing outliers remain in the evidence.

Two sequential ABBA rounds produce four fresh processes per version, each with
two warm-up calls and five two-call samples per phase/workload (20 batch means
per variant/phase). Full major GC before each sample is outside timing; allocation
and GC caused by the measured operation are inside. Current-domain `Gc.counters`
measures total allocated bytes, not retained heap or RSS; timed execution uses
one worker. Compilation, execution and end-to-end phases are separated. Setup,
trace hashing, worker checks and output printing are outside the timed region.

Every invocation executes 24 rows: eight positions (both sides of each model)
and three scenarios. The ordinary book has valuation offsets 0/7/30 days against
365-day expiry; boundaries use 0/365/366; the arithmetic-failure book uses rate
-2000. The harness fixes original input words, position weights 100/-99 and typed
limits 1e-8 before scoring. It requests price only, price/Delta, or all eleven
quantities. Repeated runs, workers 1/2 and fresh compiles preserve the complete
ordered event/status digest. No failed row is omitted or replaced with a success.

Times below are **milliseconds per complete 24-row execution**, median [min–max];
allocation is decimal MB per execution. Failure workloads are shown separately.

| Regime / outputs | Before ms | After ms | Speedup | Allocated MB before → after |
| --- | ---: | ---: | ---: | ---: |
| boundaries/1 | 7.709 [7.397–9.803] | 7.442 [7.310–10.806] | 1.04× | 38.976 → 38.977 |
| boundaries/11 | 57.409 [55.691–88.716] | 31.644 [31.032–56.085] | 1.81× | 300.261 → 160.198 |
| boundaries/2 | 13.737 [13.461–15.133] | 11.033 [10.833–17.450] | 1.25× | 71.195 → 57.189 |
| failure/1 | 0.092 [0.089–0.107] | 0.090 [0.089–0.125] | 1.03× | 0.422 → 0.425 |
| failure/11 | 1.014 [0.974–1.045] | 0.130 [0.125–0.270] | 7.82× | 4.523 → 0.517 |
| failure/2 | 0.178 [0.175–0.196] | 0.091 [0.088–0.168] | 1.95× | 0.832 → 0.434 |
| ordinary/1 | 22.927 [22.763–23.705] | 24.106 [22.621–35.695] | 0.95× | 118.645 → 118.647 |
| ordinary/11 | 176.429 [173.627–178.450] | 98.852 [96.532–200.890] | 1.78× | 923.617 → 491.446 |
| ordinary/2 | 42.019 [41.398–43.108] | 36.903 [33.564–59.131] | 1.14× | 217.190 → 173.975 |

For eleven ordinary outputs, execution drops from 176.43 to 98.85 ms (1.78×,
44% less time), with 46.8% less allocation. End-to-end medians are 178.03 to
98.40 ms (1.81×). Compilation performs no numerical preparation and has no
expected improvement; raw compile samples are retained. One-output execution
was 5.1% slower by median with overlapping ranges and effectively unchanged
allocation (+2,112 bytes per 24 rows); no single-output speedup is claimed. An
isolated measurement is needed to distinguish small timing effects from host
variation. Two-output allocation falls 19.9%, with smaller timing savings.

Ordinary success counts are 24/48/264; boundary served/failed counts are 16/8,
24/24 and 96/168. Arithmetic-failure counts are 0/24, 0/48 and 0/264. All counts,
certificate words, radii, failures and summaries match before/after. Faster
cached failures are not counted as improved availability. The broader #8 target-
environment and operational qualification remains open with #16.

## Reproduction

Create isolated worktrees at the baseline and equivalent rebased implementation
commits above.
Copy `bench/shared_portfolio.ml` and its stanza from `bench/dune` into the baseline,
then build both with the pinned switch:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --release -j 2 bench/shared_portfolio.exe
```

After all local builds and tests finish, run from the candidate:

```sh
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_shared_portfolio.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --rounds 2 --output /tmp/shared-portfolio.json
```

Run the ordinary suite and the six named mutants above using the repository
commands. `scripts/audit_planner.py` uses the optional pinned Arb/QuantLib oracle
environment; the retained report records its versions and source hashes.
`candidate_artifact.py --commit <full-SHA> --output <fresh-directory>` reproduces
the separate source installation and native/bytecode consumer checks.
