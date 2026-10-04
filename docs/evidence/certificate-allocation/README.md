# Certificate allocation evidence

The [report](../../results-certificate-allocation.md) owns interpretation.
Baseline is main `bea4620a94104ab526fb61f6919012e5f9faa309`; runtime candidate
is `d81e2302fa1b0c0a6954954169716e722ace07d5`. Both use OCaml 5.3.0 Flambda,
the same benchmark sources, default Dune profile and the library's `-O3`.
`host.json` records the environment. `SHA256.json` covers retained artifacts;
benchmark reports and `compatibility.json` pin the candidate source.

- `profile-summary.json`: separate baseline sampling, excluded from timings.
- `list-prototype.json`: negative preliminary result; not the shipped source.
- `exchange-abba.json`: all 336 exchange timing/allocation samples, loads,
  binary/source hashes and median/min/max summaries. Failures are retained.
- `assurance-abba.json`: four-model admission, fast price/Greeks, certified IV
  and end-to-end samples/outcomes; `assurance-summary.json` summarizes pairs of
  run medians. Zero-resolution control timing has no percentage conclusion.
- `compatibility.json`: exact value/radius/outcome identities. Exchange inputs
  and qualified output remain in `../exchange-qualification/`; bytecode also
  matches those 649 rows. No duplicate exchange output is needed here.
- `candidate-shadow.txt.gz`: 3,258 numerical output rows from the existing
  258-row `../shadow-campaign.json.gz` input corpus, identical to baseline.
  Timings are excluded from this compatibility artifact.
- `exchange-score.json.gz`: full independent reference containment decisions,
  using the previously qualified `../exchange-qualification/references-final.json.gz`.
- `ordinary.log.gz`, `mutations.log`: passing complete ordinary suite and five
  affected compiled numerical mutants. The ordinary suite also checks the
  catalog's 84 mechanisms and unchanged seven core selections.

## Reproduce

Build each immutable revision in an isolated worktree with the existing switch:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install \
  bench/exchange_qualification_bench.exe bench/exchange_campaign.exe \
  bench/assurance.exe bench/shadow.exe
```

From the candidate, supply the baseline worktree's absolute binary paths:

```sh
python3 scripts/benchmark_exchange_allocation.py \
  --baseline /path/to/baseline/_build/default/bench/exchange_qualification_bench.exe \
  --candidate _build/default/bench/exchange_qualification_bench.exe \
  --baseline-revision bea4620a94104ab526fb61f6919012e5f9faa309 \
  --output /tmp/exchange-abba.json
python3 scripts/benchmark_assurance.py \
  --baseline /path/to/baseline/_build/default/bench/assurance.exe \
  --candidate _build/default/bench/assurance.exe \
  --baseline-revision bea4620a94104ab526fb61f6919012e5f9faa309 \
  --same-contract --count 32 --runs 5 --output /tmp/assurance-abba.json
```

Keep profiling, tests and builds outside these timing runs. Use the same compiler,
profile and environment for both binaries. Host load remains an observed limit.

Generate the exact exchange worker input without rerunning expensive references:

```sh
python3 - <<'PY' > /tmp/exchange-input.txt
import json
fields = ('s1','s2','q1','q2','sigma1','sigma2','rho','time','limit')
rows = json.load(open('docs/evidence/exchange-qualification/cases-v1.json'))['rows']
for r in rows:
    print(r['id'], *(r['inputs'][f] for f in fields))
PY
_build/default/bench/exchange_campaign.exe < /tmp/exchange-input.txt > /tmp/exchange-output.txt
cmp /tmp/exchange-output.txt docs/evidence/exchange-qualification/runtime-v1.txt
gzip -dc docs/evidence/exchange-qualification/references-final.json.gz > /tmp/exchange-references.json
python scripts/score_exchange_qualification.py \
  --references /tmp/exchange-references.json --runtime /tmp/exchange-output.txt \
  --output /tmp/exchange-score.json
```

Scoring uses the qualified optional Python environment (python-flint 0.9.0 /
FLINT 3.6.0); ordinary builds do not depend on it. The shadow protocol is documented
by `_build/default/bench/shadow.exe --help`: emit `0:id`, model, side, the seven original input
words, quote and limit from each stored `row['input']`, tab-separated. Compare
baseline and candidate after removing `READY`, `STATS` and per-row `latency` lines.

The bytecode exchange replay links the unchanged campaign source against the
candidate's `morphiq_fp.cma` and `morphiq_risk.cma`; set `CAML_LD_LIBRARY_PATH` to
`_build/default/lib/fp` when executing. It must reproduce the same qualified file.

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @fmt
opam exec --switch=morphiq-risk-ml -- dune test -j 2
DUNE_JOBS=2 opam exec --switch=morphiq-risk-ml -- dune exec -j 2 \
  scripts/mutation/mutation.exe -- enclosure-grow-residual \
  enclosure-discarded-word enclosure-product-guard enclosure-series-tail \
  enclosure-fma-underflow
```

Build/format and ordinary tests pass on the runtime candidate; later evidence
changes do not alter its numerical source. PR platform checks remain a separate
gate; this directory does not claim a new release artifact or institutional approval.
