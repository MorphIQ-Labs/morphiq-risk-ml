# Operational campaign evidence

`final.tar.gz` is the completed seven-case local campaign at
`07fd3ff86fe48f67127fe40243138d8216839c57`. `initial.tar.gz` preserves the earlier
run at `be4677cb986e802d459eb615d3695a2d536ef766`, before source-status guard
strengthening. Both use the same native runner and configuration. No samples
within either campaign were removed. See the [results](../../results-operational-campaign.md)
and [protocol](../../operational-campaign.md) for their measured scope.

The archives contain only `.json`, `.jsonl` and `.stderr` data files, with no
executables, symlinks, absolute paths or third-party source payloads. Each contains:

- `config.json`: bytes captured before child startup.
- `report.json`: source/compiler/binary/host identity, every case/run, summaries,
  individual criteria and explicit `deployment_accepted: false`.
- `<case>-<repeat>/run.json`: original process-group observations and per-child RSS.
- `<case>-<repeat>/client-N.jsonl` and `.stderr`: original worker output/errors.

Inspect the report without extracting files:

```sh
python3 - <<'PY'
import json, tarfile
with tarfile.open('docs/evidence/operational-campaign/final.tar.gz') as archive:
    report = json.load(archive.extractfile('report.json'))
print(json.dumps({name: case['summary'] for name, case in report['cases'].items()}, indent=2))
PY
```

`integrity-controls.py` reproduces the source-state rejection controls in an
isolated temporary Git repository and an impossible-latency criterion using the
release runner. Run from the repository root after the documented release build.
`integrity-controls.json` retains the outcomes; `SHA256.json` covers both archives
and these control artifacts. Native build products remain outside the repository.

The relative artifact hashes identify retained bytes; they do not authenticate
an owner decision. Missing operational targets remain pending. No production
recommendation, independent human review or release approval is supplied here.
