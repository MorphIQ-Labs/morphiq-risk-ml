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
