#!/usr/bin/env bash
# C7 extractor — pulls the §4 cost-table cells from the
# onym-contracts feasibility branch's bench-gas pq output.
#
# Usage:
#   ./extract.sh ~/Developer/onym-contracts/.worktrees/pq-fri-feasibility/scripts/bench-gas/results-pq.jsonl
#
# Output:
#   c7/results.json   — schema documented inline below
#   c7/results-pq.jsonl — copy of the source jsonl (for audit)
#
# Prereqs: jq, python3.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-}"
if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "usage: $0 /path/to/results-pq.jsonl"
  echo
  echo "to produce the source file, in the onym-contracts repo:"
  echo "  git worktree add .worktrees/pq-fri-feasibility wt-pq-fri-feasibility"
  echo "  cd .worktrees/pq-fri-feasibility"
  echo "  bash scripts/bench-gas/run-pq.sh"
  echo "  # writes scripts/bench-gas/results-pq.{md,jsonl}"
  exit 2
fi

OUT="$HERE/results.json"
RAW="$HERE/results-pq.jsonl"

cp "$SRC" "$RAW"

python3 - "$RAW" "$OUT" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

src, out = sys.argv[1:]
rows = []
contract_addr = None
with open(src) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        if rec.get('row_type') == 'contract':
            contract_addr = rec.get('address')
            continue
        if rec.get('row_type') != 'op':
            continue
        rows.append({
            'contract': rec.get('contract'),
            'op': rec.get('op'),
            'tier': rec.get('tier'),
            'fee_stroops': rec.get('fee_stroops'),
            'tx_hash': rec.get('hash'),
            'measurable': rec.get('fee_stroops') is not None,
        })

def find(op, **kw):
    for r in rows:
        if r['op'] == op and all(r.get(k) == v for k, v in kw.items()):
            return r
    return None

deploy = find('deploy')
adm_on  = next((r for r in rows if r['op'] == 'set_restricted_mode' and r['fee_stroops'] and r['fee_stroops'] > 10000), None)
adm_off = next((r for r in rows if r['op'] == 'set_restricted_mode' and r['fee_stroops'] and r['fee_stroops'] < 10000), None)
create_group = find('create_group')
verify_m = find('verify_membership')
update_c = find('update_commitment')

unmeasurable = [r['op'] for r in rows if not r['measurable']]

out_obj = {
    'schema_version': 1,
    'source': 'onym-contracts wt-pq-fri-feasibility branch, scripts/bench-gas/results-pq.jsonl',
    'extracted': datetime.now(timezone.utc).isoformat(),
    'contract_address': contract_addr,
    'op_count_total': len(rows),
    'op_count_measurable': sum(1 for r in rows if r['measurable']),
    'op_count_unmeasurable': len(unmeasurable),
    'unmeasurable_ops': unmeasurable,
    'measured': {
        'deploy_stroops': deploy['fee_stroops'] if deploy else None,
        'set_restricted_mode_on_stroops': adm_on['fee_stroops'] if adm_on else None,
        'set_restricted_mode_off_stroops': adm_off['fee_stroops'] if adm_off else None,
    },
    'pending_pcs_layer': {
        'create_group_stroops':       create_group['fee_stroops'] if create_group else None,
        'verify_membership_stroops':  verify_m['fee_stroops']     if verify_m     else None,
        'update_commitment_stroops':  update_c['fee_stroops']     if update_c     else None,
        'note': (
          'These rows currently emit null because the on-chain verifier '
          'accepts a FRI low-degree-test proof but no batched-PCS layer '
          'binds those FRI commitments to an AIR. Re-run the upstream '
          'bench when pq/verifier/src/lib.rs lands the PCS work.'
        ),
    },
    'rows': rows,
}
Path(out).write_text(json.dumps(out_obj, indent=2))
print(f"    wrote {out}")
print(f"    measured ops: {out_obj['op_count_measurable']}")
print(f"    unmeasurable (pending PCS): {out_obj['op_count_unmeasurable']}")
PY

echo "==> done"
echo "    raw:     $RAW"
echo "    results: $OUT"
