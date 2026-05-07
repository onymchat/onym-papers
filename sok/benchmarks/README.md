# SoK first-party benchmarks

Two harnesses live here, one per first-party-measured row in the §4
comparison tables:

```
benchmarks/
├── c1/    Stellar + BLS12-381 + PLONK   — production deployment, release v0.0.5
└── c7/    Stellar + FRI-style hash-based — feasibility branch
```

Both pull from the public `onymchat/onym-contracts` repository
( https://github.com/onymchat/onym-contracts ) — the SoK's own
source tree carries only the *extraction* scripts, not the contracts.
Anyone can re-derive the table cells by re-running the upstream
contracts-repo benchmarks and re-running these extractors against
the result files.

## Quickstart — refresh the table cells

The §4 cost table currently embeds numbers extracted from
**`onym-contracts` release `v0.0.5`** (PLONK, captured 2026-05-02)
and the **`wt-pq-fri-feasibility` branch's `results-pq.{md,jsonl}`**
(C7, captured 2026-05-02).

To refresh against a newer release:

```sh
# C1 — PLONK, from a published GitHub release
cd benchmarks/c1
./extract.sh v0.0.5      # or whichever tag is current
# writes c1/results.json (schema in methodology.md)

# C7 — FRI feasibility, from a re-run of the upstream branch
git -C ~/Developer/onym-contracts worktree add \
    .worktrees/pq-fri-feasibility wt-pq-fri-feasibility
cd ~/Developer/onym-contracts/.worktrees/pq-fri-feasibility
bash scripts/bench-gas/run-pq.sh        # ~10 minutes; needs `stellar` CLI funded on testnet
cd -
cd benchmarks/c7
./extract.sh ~/Developer/onym-contracts/.worktrees/pq-fri-feasibility/scripts/bench-gas/results-pq.jsonl
# writes c7/results.json
```

After both `results.json` files are in place, regenerate the PDF:

```sh
make            # from sok/
```

## Why two harnesses

The two configurations have very different operational shapes:

| Aspect | C1 (PLONK) | C7 (FRI feasibility) |
|---|---|---|
| Status | production | feasibility branch |
| Verifier | `plonk-verifier` (BLS12-381 + EF KZG SRS) | `fri-verifier` (BN254 Fr + Poseidon2 host fn) |
| Contracts | 5 Soroban contracts | 1 Soroban contract (`pq-sep-anarchy`) |
| Proof-bearing ops measured | yes (full coverage in v0.0.5) | no — PCS layer pending |
| Source of canonical numbers | published `gh release view` body + JSONL asset | local re-run of `run-pq.sh` |
| Refresh cadence | each new tagged release | re-run when the feasibility branch advances |

A single harness would force one of the two to inherit the other's
shape; we keep them independent so the C7 extractor can grow as the
PCS layer lands without disturbing the C1 cells.

## Required tools

| Tool | Used by | Notes |
|---|---|---|
| `gh` | C1 | GitHub CLI, authenticated against `onymchat/onym-contracts` |
| `jq` | both | JSON wrangling |
| `python3` | both | the extractors compute medians and emit `results.json` |
| `stellar` | C7 | Stellar CLI v22+, used by `run-pq.sh` to deploy/invoke on testnet |
| `cargo` | C7 | builds the `gen-pq-proof` bench-only prover |
| `xxd` | C7 | proof-byte hex encoding inside `lib.sh` |

## Pinning conventions

* Every release body and JSONL asset is downloaded with the release
  tag in its filename, and the extractor records the tag plus a
  capture timestamp in the emitted `results.json`. Cross-run
  comparability is therefore preserved as long as the upstream tag
  exists.
* USD figures in the §4 tables are anchored to a single
  XLM/USD spot rate at submission time; the
  extractor writes stroops (the on-chain native unit) only, and the
  USD conversion is applied at table-render time. Re-anchor by
  editing the rate in the table caption rather than the extractor.
* The C7 extractor records when proof-bearing rows are dashes (the
  upstream JSONL emits `"fee_stroops": null` for those rows); the
  table cells then read `not yet measurable` rather than a fabricated
  value.
