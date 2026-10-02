#!/usr/bin/env bash
# Cross-check against FerroRisk's references, where a local FerroRisk
# checkout is available (oracle/fetch.sh and the convert_* scripts write
# them to oracle/data/). This is a second opinion, never the ground truth.
# The tests (dune test) use this project's own fixtures, and CI does not run
# this.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
run() {
  local exe=$1 data=$2
  if [ -f "$data" ]; then
    echo "== $exe on $data"
    dune exec "test/$exe.exe" -- "$data" | tail -n +1 || status=1
  else
    echo "-- skipped $exe: $data not present (run oracle/fetch.sh and the convert scripts)"
  fi
}
run oracle_normal oracle/data/normal_reference.txt
run oracle_price oracle/data/european_price_reference.txt
run oracle_iv oracle/data/public_iv_reference.txt
run oracle_greeks oracle/data/greek_reference.txt
exit $status
