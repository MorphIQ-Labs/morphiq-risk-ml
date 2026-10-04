# Planner scheduling and failure campaign (#56)

The [bounded protocol](planner-stress-protocol.md) passes against source
`f1ebc49aa1cdac729dffc9a101e055f96e39f0ed`: five independent subprocess runs,
44 checks each, plus four fresh-process memory observations. No implementation
failure was found. This change adds tests and evidence; runtime code and public
API are unchanged. A subsequent commit formats only the Dune test rules.

## What was exercised

A fixed 17-position book spans all four models, mixed-sign weights, ordinary and
extreme discount arguments, expiry and post-expiry, and three date scenarios.
Its price/delta/vega outputs include different numerical costs and explicit
failures. For workers 1/2/3/4 and tile sizes 1/2/5/19, tests require identical
ordered events from the public executor and the instrumented source copy.
Independent rational sums of the accepted leaf intervals must be contained in
each reported aggregate; failures and completeness are counted separately.
Plan manifests match between the two builds for identical specifications.

The additional witnesses cover:

- Empty portfolio/scenarios and zero output quantities; exact and one-below
  instrument, scenario, calculation, group and result-slot limits; checked raw
  volume overflow without allocating the enormous scenario grid.
- Negative/out-of-range tile indices, a modified logical extent in the unsealed
  test copy, and a foreign tile. Public tile construction stays private.
- Spawn rejection before any handle, after one started handle, and after a
  completed wave; tile exceptions in the coordinator and a later worker; an
  uncaught domain exception propagated through the real join operation.
- A first tile held until all three later tiles finish, followed by a slow sink.
  No next-wave dispatch occurs during a sink callback. All started domains are
  joined before callbacks and return, including each injected-failure path.
- Cancellation from a separate real domain while the coordinator's first tile
  is held, and cancellation at committed row boundaries 1/8/17/50/51. Cancelling
  during acceptance of the final row may still return Complete: no work remains
  at the next cancellation checkpoint. Tests preserve this documented checkpoint
  behavior rather than asserting a timing-dependent stop flag.
- Returned and raised sink failures at a later row, first summary and Finished
  marker. Committed counts match the accepted prefix; no callback follows sink
  failure, and interrupted scenarios do not receive fabricated summaries.

Shared observations are atomic; hook configuration is frozen before execution.
The source generator requires unique insertion sites and records the exact
`lib/planner.ml` SHA-256. It wraps tile evaluation and actual domain operations;
it does not replace scheduler decisions or add runtime callbacks. Hash identity
establishes provenance, while public/instrumented replay and independent outcome
assertions establish the exercised behavior. This is not a proof of race freedom.

## Slots and process memory are different observations

The instrumented lane counts completed rows' output slots (at least one slot
per row, including zero-output rows) retained until the wave is consumed. Each
run compares its observed peak with that plan's compiled bound and checks zero
retained slots at return. Across the finite matrix the largest observed peak was
153 slots; every plan stayed within its own bound. This counter excludes scalar
scratch, unfinished arrays, book storage, aggregation state and GC retention.

The separate memory lane executes the **public** planner with a streaming sink
that retains no event list, four workers and 32-row tiles. Each measurement has
a fresh process, with macOS `ru_maxrss` reported in bytes. The harness converts
Linux KiB explicitly when run there. The compiler was OCaml 5.3.0 Flambda, Dune
3.24.2; the recorded host was Apple M1 Pro, macOS 27 arm64, Python 3.14.8.

| Positions | Scenarios | Completed rows | Compiled slot bound | Peak RSS bytes |
| ---: | ---: | ---: | ---: | ---: |
| 256 | 1 | 256 | 384 | 15,745,024 |
| 256 | 8 | 2,048 | 384 | 18,595,840 |
| 4,096 | 1 | 4,096 | 384 | 20,971,520 |
| 4,096 | 8 | 32,768 | 384 | 23,740,416 |

The slot policy remains independent of total scenario count. RSS includes the
runtime, frozen O(book) storage, active domains, arithmetic scratch and GC heap;
these few observations do not establish a hard bound or asymptotic RSS law.
Recorded elapsed times are diagnostic metadata, not controlled throughput
benchmarks. Final GC heap words are neither peak RSS nor total live process data.

## Reproduction and limits

```sh
opam exec --switch=morphiq-risk-ml -- dune build test/planner_stress.exe
python3 scripts/planner_stress.py check _build/default/test/planner_stress.exe --repeats 5
python3 scripts/planner_stress.py memory _build/default/test/planner_stress.exe
```

Ordinary `dune test` runs one bounded stress pass and three launcher/source-hook
controls. Each stress subprocess has a 90-second deadline; memory children have
120 seconds and an enclosing 125-second deadline. Barrier waits have five-second
limits. Timeout, nonzero process exit, malformed JSON, missing executable or
ambiguous instrumentation fails the gate; none counts as a successful finding.
The optional repeat count is bounded at 50. Memory runs remain manual.

The [retained reports](evidence/planner-stress/) include exact parameters,
source/runner hashes, tool versions and every measured run. Local
`dune build @install @fmt @runtest -j 2` passed, including existing reference,
planner, property and type checks. No runtime numerical path or seven-mutant CI
selection changed; no new numerical mutation-kill claim is made.

Unexercised mechanisms include arbitrary OS scheduling, actual system-wide
resource exhaustion, process crashes, asynchronous interruption, unbounded
consumer blocking and every possible cancellation interleaving. Failure wrappers
simulate reachable exception boundaries without claiming to reproduce every
operating-system failure. There is no distributed execution, resume or durable
exactly-once delivery claim. This evidence feeds #57 and the #15 review package;
no independent human review or institutional approval has occurred here.
