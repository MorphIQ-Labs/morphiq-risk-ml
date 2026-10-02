#!/usr/bin/env bash
# Read the slice's independent reference fixtures from a pinned FerroRisk
# commit (the !551 head; move to its squash-merge commit once it lands).
set -euo pipefail
PIN=12b5081a30a8ddea214f59bf6cb04f7b1e2d9728
FERRO_RISK=${FERRO_RISK:-$(cd "$(dirname "$0")/../../ferro-risk" && pwd)}
OUT="$(cd "$(dirname "$0")" && pwd)/data"
mkdir -p "$OUT"
git -C "$FERRO_RISK" cat-file -e "$PIN^{commit}" || git -C "$FERRO_RISK" fetch -q origin "$PIN"
for f in normal_premium_reference public_iv_reference iv_inverse_reference \
         bachelier_quantlib_reference greek_derivative_reference black_greek_boundary_reference; do
  git -C "$FERRO_RISK" show "$PIN:crates/ferro-risk/testing/data/$f.json" > "$OUT/$f.json"
done
printf '%s\n' "$PIN" > "$OUT/PIN"
