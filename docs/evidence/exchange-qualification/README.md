# Reproducing the exchange qualification

Runtime candidate: `6226b8a8cb35c765c83c97c02dd58d8d15bcde40`.
Protocol/case freeze: `2e8a5d7`; reference refinements: `baf15df`, `3db4e33`;
local qualification harness/results: `8b964cc`. Later dossier-only changes do
not replace the runtime candidate. `SOURCE_SHA256.json` pins the final numerical
reference/scoring/property/harness owners; `SHA256.json` covers retained data.
The original v1 source lives in `generator-v1.py` and its freeze commit; the
aborted v2 reference source is `reference-v2.py`. Historical copies are evidence,
not scripts to execute from this directory with their old relative paths.

Use OCaml 5.3.0 Flambda and the existing project switch. Oracle commands require
the optional pinned Python 3.14.8, python-flint 0.9.0 / FLINT 3.6.0 environment;
ordinary builds remain independent of it and private research storage.

```sh
opam exec --switch=morphiq-risk-ml -- dune build bench/exchange_campaign.exe
python scripts/exchange_qualification.py reference --output /tmp/exchange-v3.json
python scripts/exchange_tail_adjudication.py \
  --references /tmp/exchange-v3.json --output /tmp/exchange-tail.json
python scripts/exchange_deficit_reference.py \
  --references /tmp/exchange-tail.json --output /tmp/exchange-final.json
python - <<'PY'
import json
from pathlib import Path
rows=json.loads(Path('docs/evidence/exchange-qualification/cases-v1.json').read_text())['rows']
Path('/tmp/exchange-input.txt').write_text(''.join(
    r['id']+' '+' '.join(r['inputs'].values())+'\n' for r in rows))
PY
_build/default/bench/exchange_campaign.exe < /tmp/exchange-input.txt > /tmp/exchange-runtime.txt
python scripts/score_exchange_qualification.py \
  --references /tmp/exchange-final.json --runtime /tmp/exchange-runtime.txt \
  --output /tmp/exchange-score.json
python scripts/exchange_properties.py \
  --cases docs/evidence/exchange-qualification/cases-v1.json \
  --runtime /tmp/exchange-runtime.txt --output /tmp/exchange-properties.json
python scripts/test_exchange_qualification.py
```

The final reference keeps each original input and attached prior unresolved
record; tail and deficit adjudications identify their parent bytes and tool
hashes. The v1 score, v2 aborted diagnostic and v3 pre-adjudication results are
retained separately. `runtime-v1.txt` is the unchanged candidate trace used by
every scoring pass; no runtime result was substituted during reference work.
The final independent reference status is interval for 640 mathematically
valid requests, with seven invalid inputs and two invalid accuracy requests.
Only the 625 actually served results count as numerical containment passes.

To check retained results without rerunning expensive references, decompress
`references-final.json.gz` and score it against `runtime-v1.txt` using the same
scorer. Run the paired benchmark with
`dune exec bench/exchange_qualification_bench.exe`; record current host load
and do not compare its timings as if the machine were idle. Every qualification
artifact and numerical conclusion belongs to its recorded source/toolchain.

The optional QuantLib runner and build commands are retained in the
[implementation record](../../exchange-prices.md). Feed it the same input table;
three rate rows per case are preserved in `quantlib.tsv`. Recreate per-case
comparisons with `scripts/exchange_qualification_canonical.py` and the compressed
final reference archive. Nonfinite/invalid/date exclusions are not comparisons.

Remote artifact evidence comes from candidate workflow run `37215290973`, not
from a branch-tip build. Retained reports distinguish its previous installed
consumer from the supplemental local Exchange consumer and full 649-case
native/bytecode replay. No remote platform is claimed to have run the broader
corpus merely because its smaller ordinary exchange suite passed.
