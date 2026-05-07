# C7 (FRI feasibility) measurement methodology

This document records the measurement contract for the row labeled C7
in §4's comparison tables.

## What is measured

* The deploy fee for a single Soroban contract built from
  `pq/sep-anarchy/` on the `wt-pq-fri-feasibility` branch of
  `onymchat/onym-contracts`. The contract embeds a `fri-verifier`
  shared crate compiled to no_std WASM that accepts a FRI
  low-degree-test proof, with an in-circuit Poseidon2-W16 sponge
  bound to the `env.crypto().poseidon2_*` Soroban host primitive
  added by Stellar CAP-0075.
* The fee for both edges of a `set_restricted_mode` admin toggle.

## What is **not** measured

* The proof-bearing entrypoints (`create_group`,
  `verify_membership`, `update_commitment`). These produce
  `fee_stroops: null` rows in the upstream JSONL because the
  feasibility-branch verifier does not yet carry a batched-PCS
  layer tying FRI commitments to an AIR. The `pq/prover/` crate
  produces self-consistent low-degree-test proofs the verifier
  accepts at bench-scope parameters (`log_n=6`, `num_layers=3`,
  `num_queries=8`, `blowup=2`), but those proofs do not bind any
  circuit witness, so a measurement of their on-chain cost would
  not be a measurement of the C7 configuration the §3 taxonomy
  describes.
* Prover wall-clock. The `gen-pq-proof` binary is bench-only and the
  upstream driver does not currently capture its runtime.

## Hardware and software pinning

The `wt-pq-fri-feasibility` worktree expects:

* `stellar` CLI v22+ with a friendbot-funded testnet identity.
* `cargo` with rustc 1.91+, matching `pq/*/rust-toolchain.toml`.
* `jq`, `xxd`, `python3` for the bench driver's invocation
  scaffolding.

Hardware pinning at submission time (TODO if the row gets re-run):

```
HARDWARE_CPU="TODO"
HARDWARE_RAM="TODO"
HARDWARE_THREADS_BASELINE=1
```

## Reproduction

```sh
git -C ~/Developer/onym-contracts worktree add \
    .worktrees/pq-fri-feasibility wt-pq-fri-feasibility
cd ~/Developer/onym-contracts/.worktrees/pq-fri-feasibility
bash scripts/bench-gas/run-pq.sh
# writes scripts/bench-gas/results-pq.{md,jsonl}

cd -                                            # back to sok/
bash benchmarks/c7/extract.sh \
    ~/Developer/onym-contracts/.worktrees/pq-fri-feasibility/scripts/bench-gas/results-pq.jsonl
# writes benchmarks/c7/results.json

make                                            # rebuild the PDF
```

## Schema of `results.json`

```
{
  "schema_version": 1,
  "source": "onym-contracts wt-pq-fri-feasibility branch, ...",
  "extracted": "<UTC ISO-8601>",
  "contract_address": "<Stellar testnet contract id>",
  "op_count_total":         <int>,
  "op_count_measurable":    <int>,
  "op_count_unmeasurable":  <int>,
  "unmeasurable_ops":  [<op names that emit fee_stroops: null>],
  "measured": {
    "deploy_stroops":                <int|null>,
    "set_restricted_mode_on_stroops":  <int|null>,
    "set_restricted_mode_off_stroops": <int|null>
  },
  "pending_pcs_layer": {
    "create_group_stroops":       null,
    "verify_membership_stroops":  null,
    "update_commitment_stroops":  null,
    "note": "..."
  },
  "rows": [<every per-op record from the upstream JSONL>]
}
```

## When this row will be measurable end-to-end

When the `verifier_pcs` follow-up referenced by
`pq/verifier/src/lib.rs` lands in the upstream branch (a batched-PCS
layer such as the canonical Plonky3 PCS-against-FRI binding, or a
Cairo-style alternative AIR encoding). At that point the
proof-bearing rows in the upstream JSONL stop emitting
`fee_stroops: null`, and a re-run of `extract.sh` against the new
JSONL will populate the C7 verify-cost cells in `results.json` (and,
via the §4 table caption, the PDF).
