# Installed Exchange campaign

The optional candidate artifact lane now compiles the existing
`bench/exchange_campaign.ml` using only the isolated installed public package.
It replays the frozen 649 original-word requests in both native and bytecode
modes against the qualified outcome/value/error-radius file. This extends the
existing installed smoke test, which already checks an ordinary Exchange price,
exact expiry and invalid accuracy.

The owner is `scripts/candidate_artifact.py`. It verifies the installed package
origin before compiling consumers, requires the full corpus and matching unique
case IDs/order, and rejects missing, extra, reordered or changed output rows.
A failed compile, nonzero exit or 900-second worker timeout aborts validation.
The timeout bounds the validation tool, not a library latency guarantee.
The ordinary `scripts/test_closeout.py` controls deliberately change values,
radii and failure classes and remove/duplicate/reorder rows to test rejection.

`report.json` adds an `exchange_replay` record with corpus, reference and consumer
hashes; native/bytecode output hashes; row counts; and every outcome count.
The optional three-platform workflow retains both output files alongside its
existing source archive, installation reports and logs. The expected distribution
is 625 served, 10 numerical failures, five accuracy refusals, seven invalid inputs
and two invalid-accuracy controls. Every row remains in the replay denominator.

This is a package and portability replay, not independent oracle regeneration.
The [exchange qualification](exchange-qualification.md) supplies the independently
bounded references and their retained limitations. Expected outputs are taken
from the immutable candidate's qualified evidence, never generated from the
installed worker being checked. Deliberate later numerical changes require their
own qualification and stability review before updating that expectation.

## Reproduction and scope

Use the artifact script from the exact candidate revision, the pinned OCaml
5.3.0 Flambda switch, and a fresh output directory:

```sh
python3 scripts/candidate_artifact.py --commit FULL_CANDIDATE_SHA \
  --output /tmp/exchange-installed-candidate
```

After that commit has merged into main, the existing manual lane performs the
same check on Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64:

```sh
gh workflow run candidate.yml --repo MorphIQ-Labs/morphiq-risk-ml --ref main \
  -f commit=FULL_CANDIDATE_SHA
```

The script rejects tool/source mismatch and reconstructs the source archive
twice. Builds, isolated package resolution, notice checks and prior installed
consumers remain required. The new full replay runs only in the manual candidate
lane; default PR CI keeps its ordinary suite and seven core mutants. This work
changes no library source, version, accuracy budget or release decision.

The [review handoff](independent-review-package.md) identifies the Exchange and
shared-enclosure deltas awaiting independent human assessment. A source-bound
artifact report records only the platform actually executed; installing this
gate alone is not evidence of a completed three-platform campaign.


## Executed local rehearsal

Source `310b39c1b8aacf1aec72b085f2e2d347be8268bd` passes the complete artifact
procedure on macOS ARM64 with OCaml 5.3.0 Flambda. The
[retained report](evidence/installed-exchange/local-310b39c.json) records all
installed file/notice hashes and package origin. Both modes reproduce all 649
rows, with output SHA-256
`0b9430f73d941565f194a416837294d12de2316883f9a1db2686a2a20827ab0a`, identical to
the qualified reference. The reproducible source archive has SHA-256
`d7690f4cdcea3f8aeaec5220739a74125f78ea0f6105dd8293eb087551ee37e6`.

The original archive, build log and report are also preserved locally under
`~/Library/Application Support/MorphIQ Labs/acceptance/morphiq-risk-ml/310b39c1b8aacf1aec72b085f2e2d347be8268bd/`.
This is not a public build dependency. Build/install, formatting, the four
closeout control tests and `actionlint` pass. The library and campaign consumer
are unchanged from main `7fb59a3`; this rehearsal changes no numerical evidence
or output expectation. Three-platform execution remains a separate post-merge
manual candidate run; this local receipt does not claim its result.
