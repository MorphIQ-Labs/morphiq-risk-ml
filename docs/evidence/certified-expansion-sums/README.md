# Certified expansion sum evidence

See [the report](../../results-certified-expansion-sums.md) for scope and conclusions.
`scalar-abba.json.gz` retains original checks, timings, CPU/allocation, source and
binary hashes; `portfolio-abba.json.gz`, `exchange-abba.json.gz` and both
`assurance*-abba.json.gz` retain consumer comparisons. The first assurance run
is not discarded when reporting its less interrupted repeat.

`validation*.log.gz` includes the initial bytecode DLL configuration error and
later successful ordinary/build/format completion. `mutations.log.gz` records a
missing guard-dispatch mapping; it is a harness failure, not a mutant kill.
`mutations-final.log.gz` records the clean baseline and nine valid kills.
`replay.json` and `installed-artifact.json` retain complete public-output and
installed-consumer checks. Source artifacts remain outside the public checkout.

`sample.txt.gz` and `profile-harness.ml.gz` retain the baseline diagnostic.
`probe-abba.json.gz` and `discarded-storage-probe.ml.gz` retain the rejected
storage experiment; that source is not the production implementation.

Reproduce on the pinned opam switch, with matching benchmark sources copied to
a detached baseline worktree and built before timing:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 bench/certified_scalar.exe
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_certified_scalar.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --output /tmp/certified-scalar-abba.json
```

`SHA256.json` covers retained files. Reference campaigns are reused, not regenerated;
finite checks do not establish universal availability or independent human review.
