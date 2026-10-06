# Fixed follow-up after first latency failure

Frozen before collecting follow-up observations. The original 140-process cash
campaign completes with unchanged replay and passing allocation criteria, but
six eight-row latency criteria fail. All original samples remain evidence.
Recorded one-minute host load spans roughly 15.5–70.2; isolated stalls reach
several times ordinary wall time with substantially smaller CPU-time changes.
Unrelated workloads are active. This suggests external interference; it does not
prove that interference accounts for every candidate regression.

Run exactly twelve diagnostic processes on the eight-row piecewise-cash case:
three pairs of the baseline binary against itself, and three pairs of the
candidate binary against itself. Alternate binary and method order per round.
Use the unchanged driver, fresh processes, replay/source/binary guards and
per-child wall/CPU/RSS/load records. Evaluate both label directions against the
same 10% latency threshold as a falsification control, not an adoption gate.
No new profiler, concurrent owned compute or host settings changes.

Then run the complete unchanged 140-process campaign exactly once more.
Require all original allocation/latency thresholds on that repeat AND on
medians pooling all ten process observations per build/workload from both
campaigns. No samples may be removed; compilation/admission remain separate.
A passing repeat alone is insufficient. Validate pooling completeness/replay
and failure controls before use. If these fixed follow-up gates fail, publish
both campaigns and defer adoption rather than continue rerunning until green.
The first campaign remains failed regardless of the follow-up decision.
