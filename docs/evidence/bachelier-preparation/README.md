# Shared preparation evidence — 2026-10-05 UTC

See the [report](../../results-bachelier-preparation.md) for scope and limitations.
`timings-summary.json` contains all 360 revision/family/size/backend/phase
combinations with four process medians each. `raw.tar.gz` retains:

- `timing/`: every one of the 7,200 raw samples, stderr, source/status/binary
  guards, exact timed inputs and per-process load/UTC observations.
- `validation/`: full 110,632-row output trace, numerical scoring, local ordinary
  checks, mutation results and collector/native controls. The initial development
  log includes a compile-failure diagnostic formatting mismatch; the corrected
  aggregate check passes. Earlier collector logs predate the final 18 groups.
- `provenance.json`: compiler/host data, commands, reference input checksum and
  exact equality of the trace with PR #121's final trace.
- `SHA256SUMS`: hashes of every other member's uncompressed bytes.

The sibling `SHA256SUMS` hashes the archive and summary. All archived members
are project evidence: text or JSON. There are no binaries, third-party source
payloads, native libraries or PDFs. The unchanged original-input corpus and
independent refinement metadata are retained in
[the previous experiment archive](../fast-simd/README.md), under
`validation/input-qualified.txt` and its JSON metadata. Its input SHA-256 is
`a9794c2c9e8234854f3d0c1e0e7f760a03b73d72f38dc7e2488b7ba775367339`.

This campaign ran on a heavily loaded shared host. The report explicitly limits
its timing conclusions; retaining successful samples does not establish quiet-host
performance or deployment acceptance.
