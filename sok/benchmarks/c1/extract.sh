#!/usr/bin/env bash
# C1 extractor — pulls the §4 cost-table cells from a published
# onymchat/onym-contracts release.
#
# Usage:
#   ./extract.sh v0.0.5
#
# Output:
#   c1/results.json — schema documented in methodology.md
#   c1/release-body.md — raw release body text (for audit)
#   c1/results.jsonl  — raw per-op JSONL fee rows (for audit)
#
# Prereqs: gh (authenticated), jq, python3.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "usage: $0 <release-tag>"
  echo "       e.g. $0 v0.0.5"
  exit 2
fi

REPO="${C1_REPO:-onymchat/onym-contracts}"
OUT_DIR="$HERE"
RELEASE_MD="$OUT_DIR/release-body.md"
RAW_JSONL="$OUT_DIR/results.jsonl"
OUT="$OUT_DIR/results.json"

echo "==> fetching release body for $REPO@$TAG"
gh release view "$TAG" --repo "$REPO" --json body -q .body > "$RELEASE_MD"

echo "==> downloading per-op JSONL asset (best-effort)"
gh release download "$TAG" --repo "$REPO" \
  --pattern 'gas-benchmarks-*.jsonl' \
  --output "$RAW_JSONL" --clobber 2>/dev/null \
  || echo "    (no JSONL asset on this release; falling back to release-body parse)"

CAPTURE_TS="$(grep -oE '\*\*Captured:\*\* [^ ]+' "$RELEASE_MD" \
              | head -1 | awk '{print $2}' || echo unknown)"

# Extract per-op stroops by parsing the markdown table in the release
# body. The schema:
#   | Contract | Operation | Tier | Fee (XLM) | Stroops | Resource | ... |
echo "==> parsing release body table"
python3 - "$RELEASE_MD" "$OUT" "$TAG" "$CAPTURE_TS" <<'PY'
import json, re, sys, statistics
from pathlib import Path

body_path, out_path, tag, captured = sys.argv[1:]
body = Path(body_path).read_text()

rows = []
table_rx = re.compile(
    r'^\|\s*`(?P<contract>[a-z0-9-]+)`\s*\|'
    r'\s*`(?P<op>[a-z0-9_()]+)`\s*\|'
    r'\s*(?P<tier>[^|]+?)\s*\|'
    r'\s*(?P<xlm>[\d.,—-]+)\s*\|'
    r'\s*(?P<stroops>[\d,—-]+)\s*\|',
    re.MULTILINE,
)
for m in table_rx.finditer(body):
    stroops_raw = m.group('stroops').replace(',', '').strip()
    if stroops_raw in ('—', '-', ''):
        continue
    rows.append({
        'contract': m.group('contract'),
        'op': m.group('op'),
        'tier': m.group('tier').strip(),
        'fee_xlm': float(m.group('xlm').replace(',', '')) if m.group('xlm') not in ('—', '-') else None,
        'fee_stroops': int(stroops_raw),
    })

def median_stroops(*, contract=None, op=None, tier=None):
    matched = [
        r['fee_stroops'] for r in rows
        if (contract is None or r['contract'] == contract)
        and (op is None or r['op'] == op)
        and (tier is None or r['tier'] == str(tier))
    ]
    if not matched:
        return None
    return int(statistics.median(matched))

def first_stroops(*, contract, op, tier=None):
    for r in rows:
        if r['contract'] == contract and r['op'] == op:
            if tier is None or r['tier'] == str(tier):
                return r['fee_stroops']
    return None

# Aggregate cells used by §4 cost table.
out = {
    'schema_version': 1,
    'source': 'onymchat/onym-contracts release body',
    'tag': tag,
    'captured': captured,
    'op_count': len(rows),
    'aggregate': {
        # Median deploy across the 5 contracts.
        'deploy_stroops_median': median_stroops(op='deploy'),
        # Median verify_membership across all (contract, tier) pairs.
        'verify_membership_stroops_median': median_stroops(op='verify_membership'),
        # Median tier-0 create_group across contracts that have it.
        'create_group_tier0_stroops_median': median_stroops(op='create_group', tier='0'),
        # sep-anarchy tier-0 update_commitment as the canonical
        # update-shape cell.
        'update_commitment_anarchy_tier0_stroops':
            first_stroops(contract='sep-anarchy', op='update_commitment', tier='0'),
    },
    'per_contract': {
        'sep-anarchy': {
            'deploy': first_stroops(contract='sep-anarchy', op='deploy'),
            'verify_membership_tier0': first_stroops(contract='sep-anarchy', op='verify_membership', tier='0'),
            'create_group_tier0': first_stroops(contract='sep-anarchy', op='create_group', tier='0'),
            'update_commitment_tier0': first_stroops(contract='sep-anarchy', op='update_commitment', tier='0'),
        },
        'sep-democracy': {
            'deploy': first_stroops(contract='sep-democracy', op='deploy'),
            'verify_membership_tier0': first_stroops(contract='sep-democracy', op='verify_membership', tier='0'),
        },
        'sep-oligarchy': {
            'deploy': first_stroops(contract='sep-oligarchy', op='deploy'),
            'verify_membership_revert': first_stroops(contract='sep-oligarchy', op='verify_membership'),
        },
        'sep-oneonone': {
            'deploy': first_stroops(contract='sep-oneonone', op='deploy'),
            'create_group': first_stroops(contract='sep-oneonone', op='create_group'),
        },
        'sep-tyranny': {
            'deploy': first_stroops(contract='sep-tyranny', op='deploy'),
        },
    },
    'rows': rows,
}
Path(out_path).write_text(json.dumps(out, indent=2))
print(f"    wrote {out_path} with {len(rows)} op-rows")
PY

echo "==> done"
echo "    body:    $RELEASE_MD"
echo "    raw:     $RAW_JSONL"
echo "    results: $OUT"
