#!/usr/bin/env bash
# Read the slice's independent reference fixtures from a pinned FerroRisk
# commit (the !551 head; move to its squash-merge commit once it lands).
set -euo pipefail
PIN=12b5081a30a8ddea214f59bf6cb04f7b1e2d9728
FERRO_RISK=${FERRO_RISK:-$(cd "$(dirname "$0")/../../ferro-risk" && pwd)}
OUT="$(cd "$(dirname "$0")" && pwd)/data"
mkdir -p "$OUT"
git -C "$FERRO_RISK" cat-file -e "$PIN^{commit}" || git -C "$FERRO_RISK" fetch -q origin "$PIN"
# The IV references carry #448's identifiability semantics (the rounded
# zero-volatility bound), which exist only on the #448 stack tip.
IV_PIN=c1d2b66f7e1a9ec32d724aa1a9f6e1c2978a02cc
git -C "$FERRO_RISK" cat-file -e "$IV_PIN^{commit}" || git -C "$FERRO_RISK" fetch -q origin "$IV_PIN"
for f in public_iv_reference public_iv_observed_envelope; do
  git -C "$FERRO_RISK" show "$IV_PIN:crates/ferro-risk/testing/data/$f.json" > "$OUT/$f.json"
done
for f in normal_premium_reference iv_inverse_reference \
         bachelier_quantlib_reference greek_derivative_reference black_greek_boundary_reference; do
  git -C "$FERRO_RISK" show "$PIN:crates/ferro-risk/testing/data/$f.json" > "$OUT/$f.json"
done
for f in candidates oracle; do
  git -C "$FERRO_RISK" show "$PIN:crates/ferro-risk/docs/440-european-formulation-evidence/$f.jsonl.gz" > "$OUT/440-$f.jsonl.gz"
done
printf '%s\n%s\n' "$PIN" "$IV_PIN" > "$OUT/PIN"
