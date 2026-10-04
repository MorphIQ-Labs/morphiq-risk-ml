# Planner stress protocol (#56)

This campaign extends the existing planner contract and rational aggregation
checks. It exercises finite schedules and resource boundaries; it does not
establish race freedom or a hard process-memory bound.

The ordinary lane uses a fixed heterogeneous book, worker counts 1/2/3/4 and
several tile sizes, exact event comparison, independent rational aggregation
of accepted leaf intervals, and explicit failure/completion accounting. It
covers empty dimensions, zero outputs, foreign/invalid tiles, resource limits,
slow early work, slow sinks, concurrent cancellation and returned/raised sink
failures at row, summary and completion boundaries. Every subprocess has a
wall-clock deadline. Larger repeated and memory runs remain manual.

Fault injection is confined to a generated test build of `lib/planner.ml`.
The generator records the source hash and requires unique hook sites. The
scheduler, ordering, arithmetic and exception handling are copied unchanged;
test wrappers surround tile evaluation and real `Domain.spawn`/`Domain.join`.
They inject a spawn rejection, a tile exception and an uncaught domain exception,
coordinate delayed work, and observe domain/slot counts. No production callback,
unsafe cast, global runtime hook or runtime dependency is added. An unperturbed
instrumented run must match the public planner's event trace. The source hash is
provenance; behavioral checks supply the evidence.

All started real domains must be joined before sink callbacks and return, even
after failure. Ordered accepted rows are the committed prefix; no broken sink
is promised a terminal marker, and no incomplete scenario may have a complete
summary. Cancellation can race with completion of the last committed row;
assert supported stop/accounting relationships rather than timing guesses.

Observe completed result rows/output slots retained within a wave separately
from process memory. This observation excludes scalar scratch, frozen book,
aggregation state and GC retention. Measure peak process RSS in fresh
subprocesses for varying book/scenario sizes; record units and platform and do
not equate RSS with the advertised slot bound or fit a hard memory guarantee
from a few measurements. Retain source/tool versions, exact case parameters,
pass/failure reports and reproducible commands.
