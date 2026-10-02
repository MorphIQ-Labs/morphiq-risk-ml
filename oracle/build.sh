#!/usr/bin/env bash
# Regenerate every oracle fixture and the manifest that pins it.
#
#   python3 -m venv oracle/.venv && oracle/.venv/bin/pip install mpmath==1.3.0
#   oracle/build.sh            # all fixtures (about an hour on one core)
#   oracle/build.sh european   # one fixture
#
# Each fixture is written uncompressed, then gzip -n -9 (no name or time
# stamp, so identical content gives identical bytes), and
# write_manifest.py records its generator and fixture hashes (oracle/MANIFEST).
set -euo pipefail
cd "$(dirname "$0")"
PY=.venv/bin/python
generator() {
  case "$1" in
    elementary | normal | european | displaced | iv | greeks) echo "gen_$1.py" ;;
    *) echo "unknown fixture: $1" >&2; exit 2 ;;
  esac
}
if [ $# -eq 0 ]; then set -- elementary normal european displaced iv greeks; fi
mkdir -p fixtures
for name in "$@"; do
  gen=$(generator "$name")
  echo "== $name ($gen)" >&2
  "$PY" "$gen" "fixtures/$name.txt"
  gzip -n -9 -f "fixtures/$name.txt"
done
"$PY" write_manifest.py
