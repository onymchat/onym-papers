# C1 benchmark harness — methodology

Configuration measured: Stellar (Soroban) + BLS12-381 + **PLONK with KZG
commitments** + Poseidon, deployed as **five separate Soroban contracts**
(one policy per contract), with all proving and verifying keys derived
from the **Ethereum Foundation KZG Summoning Ceremony** SRS.
Per-contract measurements are the unit of report; the §4 table cells
aggregate or split per contract as called out in each table caption.

The headline deliverable is a defensible **USD per state-update operation**
at the deployment's modal membership-set size, anchored to a fixed
XLM/USD snapshot. Everything else in this document supports that number.

## Quick-start

```sh
# 1. Pin software, SRS hashes, and contract slots in run.sh.
$EDITOR run.sh

# 2. Run the harness.
bash run.sh

# 3. Inspect the headline number.
jq '.aggregate.update.medium.usd_p50' results.json

# 4. Regenerate the paper with the fresh numbers.
( cd ../.. && make )
```

## The five contracts

The deployment under measurement consists of five Soroban contracts,
each pinned to one policy (a distinct authorization predicate over the
registry's update relation). Each contract holds two relations
(membership and update) compiled at three circuit-size tiers (small,
medium, large), giving six verifying keys per contract and thirty
verifying keys across the deployment. All thirty verifying keys derive
from a single SRS — the Ethereum Foundation KZG ceremony — which is
the headline trust-posture property distinguishing C1 from the
per-circuit-MPC Groth16 configurations (C2) in the comparison tables.
Slot order is fixed by this file and matches the `c1.contract_*` keys
in `results.json`.

| Slot | `results.json` key | Policy / relation                                         | Notes                                                                |
|------|--------------------|-----------------------------------------------------------|----------------------------------------------------------------------|
| 1    | `c1.contract_1`    | TODO — fill name and the relation it implements           | <!-- e.g. registry / membership-tree maintenance -->                 |
| 2    | `c1.contract_2`    | TODO                                                      | <!-- e.g. update under single-admin policy -->                       |
| 3    | `c1.contract_3`    | TODO                                                      | <!-- e.g. update under any-member policy -->                         |
| 4    | `c1.contract_4`    | TODO                                                      | <!-- e.g. update under k-of-n quorum policy -->                      |
| 5    | `c1.contract_5`    | TODO                                                      | <!-- e.g. update under fixed-set policy -->                          |

The five-contract split (rather than a single contract dispatching on a
policy tag) is a property of the C1 deployment, not of the abstract
registry primitive. The §3.7 dependency analysis treats the split as
an in-circuit-hash-axis-orthogonal implementation choice; §4 reports
per-contract numbers because the per-policy circuit shapes and the
witness-construction work differ.

## Pre-measurement decisions

These pin the experimental setup. Record each choice in `results.json`'s
`hardware`, `software`, and `market` blocks. Decisions made for the
draft submission live here; downstream re-runs may revise them, with
the new choices recorded against a different `harness_commit`.

### Network: testnet, mainnet, or local

|             | Fee accounting | Resource accounting | Recommended use                       |
|-------------|----------------|---------------------|---------------------------------------|
| local       | none           | identical to mainnet| dev iteration during harness work     |
| testnet     | free           | identical to mainnet| sample-density runs (100 samples / unit) |
| **mainnet** | **billed**     | **authoritative**   | **headline numbers locked in paper**  |

**Plan:** dev iteration in local; statistical runs on testnet; the
single headline USD number locked from a mainnet pass. Both testnet
resource-units and mainnet stroops are recorded; the paper's `tab-cost`
C1 row anchors to the mainnet stroops.

### Sample size per measurement unit

100 samples → tight p50 / p95 bands, ~5 min per unit. With 30 units,
total ~2.5 hours wall-clock and ~$1–5 of mainnet fees for the headline
pass. Lower sample counts (e.g. 25) are acceptable for testnet
exploration; the headline mainnet pass should use ≥100.

### XLM/USD snapshot

A single instant (e.g. UTC midnight on the run day) pinned via a named
spot source (Coinbase or CoinGecko). Recorded in
`results.json:market.xlm_usd` and `market.snapshot_iso8601`. All USD
figures in the paper anchor to this rate. Re-runs at later dates pin
a new snapshot and produce a new `harness_commit`-tagged
`results.json`.

### Headline tier

The C1 row in `tab-cost-comparison.tex` reports per-tier sub-rows
(small / medium / large) plus an aggregate. The single-number
headline used in the abstract and §7.1 corresponds to the
**medium** tier — the deployment's modal membership-set size class.

## SRS provenance and supply-chain hashes

The C1 deployment uses the SRS produced by the Ethereum Foundation
KZG Summoning Ceremony (~141,000 contributors, Aug 2022 – Nov 2023).
The supply-chain pinning is what gives a third-party reviewer a
deterministic artifact to verify against, and `results.json` records
the chain explicitly:

- **Upstream transcript SHA-256** — the hash of the EF ceremony's
  published JSON transcript, pinned in
  `src/prover/srs/README.md` of the contract source tree.
- **Extracted SRS binary SHA-256** — the hash of the binary form
  the prover and verifier consume, pinned in
  `src/prover/srs/expected-hash.in` and enforced at every
  `cargo build --features plonk`.
- **Per-tier verifying-key SHA-256** — each of the small / medium /
  large verifying keys baked from the SRS is hashed and recorded
  (mirrored in `docs/cross-platform-test-vectors.json`).
- **Contract WASM hash** — each deployed contract's WASM bytecode
  embeds its verifying-key bytes via `include_bytes!`, so the WASM
  hash transitively binds the verifying key (and through it, the
  SRS).

`results.json` records every hash in the chain. A reviewer can
re-fetch the EF transcript, re-extract, re-bake, and check every
hash matches the deployed contract WASM, end-to-end. `make
benchmarks` aborts before any measurement if the chain doesn't
verify.

## What is timed and what is not

Timed (counted toward the reported wall-clock and verification cost):

- Prover wall-clock from witness-ready to proof-bytes-ready.
- On-chain verification: the Soroban host's PLONK / KZG verify call,
  including BLS12-381 pairing and $\mathbb{G}_1$ scalar-multiplication
  host functions (`stellar-cap-0059`), Poseidon permutation host
  functions (`stellar-cap-0075`), and the contract entry-point
  dispatch.
- Resource accounting in stroops via the Soroban resource meter:
  read / write entries, instructions, ledger I/O.

Not timed (excluded from the reported numbers; mentioned in the
paper's side-channel-observer party class):

- Network round-trip from client to RPC.
- Transaction signing.
- Mempool inclusion delay.
- Off-chain witness-construction time. Witness construction is
  reported separately under
  `c1.contract_<n>.witness_construction_ms` in the schema, not
  folded into prover wall-clock.
- SRS load / verifying-key load time at process startup. The KZG SRS
  is loaded once per prover process; the harness amortizes this over
  many proofs and does not include it in the per-proof wall-clock.

## Calibration baseline

Before measuring any verify call, the harness submits a no-op contract
invocation and records its fee. Every reported per-verify number
**subtracts the calibration baseline**, so the table cells report
*marginal cost of verifying a PLONK proof* rather than *cost of any
Soroban tx*.

```sh
soroban contract invoke --id $NOOP_CONTRACT --fn ping
# Emits: fee_charged_stroops, resource_units_total, tx_size_bytes.
# Recorded under c1.calibration.baseline_*.
```

The baseline is captured once per harness run, not once per sample. If
the protocol's resource-fee schedule changes between runs (a Stellar
protocol-version upgrade), the baseline must be recaptured; this is
why `software.stellar_core_version` is part of the pinning data.

## Per-unit measurement loop

For each measurement unit (5 contracts × {membership, update} × 3
tiers = 30 units), the harness runs N samples (default N = 100):

```
for i in 1..N:
  witness  = gen_witness(contract = P, relation = R, tier = T)
  t0       = now()
  proof    = prove(witness, vk = $VK)
  t1       = now()
  result   = soroban_invoke(verify_$R, args = proof)
  record:
    prover_ms        = t1 - t0
    fee_stroops      = result.fee_charged - baseline_stroops
    resource_units   = result.resource_units_total - baseline_resource_units
    tx_size_bytes    = result.tx_size
```

Per measurement unit, the harness then computes:

- `prover.wall_clock_ms_p50` and `_p95` — distribution over the N
  samples.
- `verifier.stroops_p50` and `_p95` — net of calibration baseline.
- `verifier.resource_units_p50` and `_p95`.
- `verifier.usd_p50` = `stroops_p50 × (xlm_usd / 1e7)`.

The aggregate-row C1 cell in `tab-cost-comparison.tex` reads
`aggregate.update.medium.usd_p50`. The five C1.1–C1.5 sub-rows read
`contract_<n>.update.medium.usd_p50` directly. The
`tab-prover-time.tex` C1 cell reads
`aggregate.update.medium.prover_ms_p50`.

### Variance to watch for

- **Per-policy variance across the 5 contracts** at fixed (relation,
  tier): if more than ~10% the verify call shapes differ in some
  way the SRS-reuse claim does not capture, and §5.1 / §4.1 may need
  a sub-paragraph naming the difference.
- **Per-sample variance within a unit** with p95/p50 > 1.3: usually
  network latency contaminating fee accounting (rare on Soroban; more
  common if off-chain RTT is included in error). Re-run the affected
  unit on a less loaded RPC.
- **Resource-unit ceilings**: if any tier hits Soroban's per-tx
  resource limit, the verify won't fit; report the unit as
  *infeasible at this tier* — that is itself a finding for §4.

## Hardware and software pinning

Hardware:

- TODO — pin specific machine (CPU, RAM, single vs.\ multi-thread).
- The single-threaded baseline is the headline number; multi-thread
  scaling is reported as a separate field.
- For reviewer-reproducibility, an alternative pass on a neutral
  baseline (e.g. AWS `c7i.xlarge`) is recommended; record the
  prover-wall-clock multiplier under `hardware.alternative_*`.

Software:

- TODO — pin Soroban host version, Stellar Core version, `soroban-cli`
  version.
- TODO — pin proving-toolchain version (e.g. `jf-plonk` revision)
  and the Poseidon parameter set (rate, capacity, S-box).
- SRS source: Ethereum Foundation KZG Summoning Ceremony final
  transcript; pin the transcript SHA-256 in the harness output.

Re-running the harness with different pinning produces a different
`results.json`; cross-revision comparison is a separate exercise and
is not in scope for this paper's measurement contract.

## `results.json` schema (v1)

Top-level shape:

```json
{
  "schema_version": 1,
  "anchor_date":    "2026-04-DD",
  "harness_commit": "<git sha of this paper's source tree>",
  "network":        "mainnet | testnet | local",
  "hardware":       { "...pinning fields..." },
  "software":       { "...pinning fields..." },
  "market": {
    "xlm_usd":           "<float>",
    "snapshot_source":   "coinbase | coingecko | ...",
    "snapshot_iso8601":  "<UTC timestamp at which xlm_usd was sampled>"
  },
  "srs": {
    "source":               "ethereum-foundation-kzg-ceremony-2023",
    "transcript_sha256":    "<TODO: fill at run time>",
    "extracted_bin_sha256": "<TODO>",
    "vk_sha256_small":      "<TODO>",
    "vk_sha256_medium":     "<TODO>",
    "vk_sha256_large":      "<TODO>"
  },
  "calibration": {
    "baseline_stroops":        "<int — no-op tx fee>",
    "baseline_resource_units": "<int>",
    "baseline_tx_size_bytes":  "<int>"
  },
  "c1": {
    "contract_1": { "...per-contract fields..." },
    "contract_2": { "...per-contract fields..." },
    "contract_3": { "...per-contract fields..." },
    "contract_4": { "...per-contract fields..." },
    "contract_5": { "...per-contract fields..." }
  },
  "aggregate": { "...derived fields used in single-row tables..." }
}
```

Per-contract fields (`c1.contract_<n>`):

- `contract_name` — string, the user-facing name (matches the slot
  in the table above once filled).
- `wasm_sha256` — hex string, the deployed WASM bytecode hash; closes
  the supply-chain pinning loop.
- `vk_size_bytes_per_tier` — object with keys `mem_small`,
  `mem_medium`, `mem_large`, `upd_small`, `upd_medium`, `upd_large`,
  integer values.
- `proof_size_bytes` — integer; expected to be ~700 across all
  contracts under PLONK / KZG over BLS12-381 with compressed encoding.
- `samples` — object with one entry per (relation, tier), each holding
  the per-sample raw measurements:
  ```json
  "samples": {
    "update.medium": [
      { "i": 0, "prover_ms": 234, "stroops": 51200,
        "resource_units": 6420000, "tx_size_bytes": 1024 },
      ... (N entries)
    ]
  }
  ```
- Aggregated fields per (relation, tier), computed from `samples`:
  - `<rel>.<tier>.prover_ms_p50` / `_p95`
  - `<rel>.<tier>.stroops_p50` / `_p95`
  - `<rel>.<tier>.resource_units_p50` / `_p95`
  - `<rel>.<tier>.usd_p50` / `_p95`
- `prover.wall_clock_ms_threads_<k>` — multi-thread variants for
  $k \in \{2, 4, 8\}$, optional.

Aggregate fields (`aggregate`):

- `proof_size_bytes` — single value if all contracts share it
  (expected for PLONK with a fixed proof shape).
- `<rel>.<tier>.usd_p50` / `_p95` — distribution across the five
  contracts at each (relation, tier). The headline-number cell that
  the §4 table consumes is `aggregate.update.medium.usd_p50`.
- `<rel>.<tier>.prover_ms_p50` / `_p95` — distribution across the
  five contracts; consumed by `tab-prover-time.tex`.

The aggregate fields are what the single-row C1 cells in
`tab-cost-comparison.tex` and `tab-prover-time.tex` consume. The
per-contract sub-rows in `tab-cost-comparison.tex` (when rendered
with sub-rows enabled) consume `c1.contract_<n>` directly.

## Headline deliverables

Mapped from `results.json` to the §4 paper artifacts:

| Artifact                                              | `results.json` source                       | Goes into                       |
|-------------------------------------------------------|---------------------------------------------|---------------------------------|
| Single USD per state-update headline                  | `aggregate.update.medium.usd_p50`           | abstract, §4.1, §7.1            |
| Per-tier USD breakdown                                | `aggregate.update.{small,medium,large}.usd_p50` | tab-cost C1 sub-rows        |
| Per-policy USD breakdown                              | `contract_<n>.update.medium.usd_p50`        | tab-cost C1.1–C1.5 sub-rows     |
| Prover wall-clock median (medium tier)                | `aggregate.update.medium.prover_ms_p50`     | tab-prover-time C1              |
| Proof size                                            | `aggregate.proof_size_bytes`                | tab-proof-size C1               |

A representative paper sentence: *"Across the five contracts at the
medium tier, the median USD cost of a state-update verification on
Stellar mainnet, anchored to YYYY-MM-DD XLM/USD = $X.XXXX, is
$X.XXXX."*

## Comparative anchors (optional but recommended)

To make the C1 row defensible relative to the cited rows in `tab-cost`:

1. **C2 (Eth L1, Groth16, Tornado-style)**: re-verify the cited
   ~220K-gas figure against a current Tornado verifier on Sepolia or
   a forked-mainnet harness. Fee = gas × gas_price × ETH/USD,
   anchored to the same date as the C1 snapshot.
2. **C3 (Aztec UltraPlonk)**: pull from Aztec's published L2 fee
   data; pin the version.
3. **C6 (StarkNet STARK)**: submit a test verify on StarkNet
   sepolia; record fee in STRK and convert to USD at the snapshot
   date.

For each, capture in `results.json:external` so the comparison table
has the same anchor date as the C1 row.

## Sensitivity & robustness (optional, valuable before submission)

1. **Anchor-date sensitivity**: re-run the harness on three different
   dates spanning a month; confirm the order-of-magnitude position
   of C1 in the `tab-cost` ranking does not flip. Stellar's flat-fee
   schedule should make this stable; verify, do not assume.
2. **Hardware sensitivity for prover wall-clock**: re-run on a
   neutral baseline machine (e.g. AWS `c7i.xlarge`) and report the
   multiplier in `hardware.alternative_*`.
3. **Membership-set growth at the medium tier**: sweep
   set cardinality from 16 → 128 in factor-of-2 steps. Confirm
   verifier cost is approximately constant (PLONK proof size and
   verify cost are constant in the membership set) and prover cost
   grows polynomially. Worth one figure or one paragraph in §5.1.

## Re-running

`bash run.sh` from this directory writes `results.json`. The
Makefile's `make benchmarks` target wraps this. The harness is
idempotent: re-running overwrites `results.json` in place. The
paper's table cells re-read `results.json` at the next `make`.

A small renderer (`render-table-cells.sh` or equivalent) emits LaTeX
`\newcommand{\CIaggregateUSD}{0.0042}`-style snippets from
`results.json` and the §4 tables `\input` those snippets in place of
literal `TBD` cells. This closes the loop the source tree was
designed for: a fresh harness run regenerates the PDF with current
numbers in one `make`.

## Risks and known issues

| Risk | Mitigation |
|------|-----------|
| Soroban tx-size limit (~64 KB after Protocol 22) blocks large-tier proofs | Verify proof + public inputs fit; if not, split verification or report large tier as infeasible |
| jf-plonk verifier hot path on Soroban hits the per-tx instruction budget | Profile via `--cpu-profile`; if the budget is exhausted, the configuration may need a per-tier verifier specialization, which is itself a §4 finding |
| XLM price volatility makes single-snapshot anchoring misleading | Report median over a 3-day window if Phase-5 sensitivity reveals >10% drift, or state the snapshot inline at every USD figure |
| Soroban resource-fee schedule changes between Stellar protocol versions | Recapture the calibration baseline at every protocol-version change; record `software.stellar_core_version` strictly |

## Reproducibility caveats

- The Soroban host's resource accounting changes between protocol
  versions; the measurement is anchored to the protocol version
  stated in `software`. Cross-protocol comparisons require re-running.
- The XLM/USD spot rate is a moving target; the `anchor_date` and
  `market.snapshot_iso8601` fields fix a single rate per harness
  run. Reviewers wanting current numbers should re-run the harness
  rather than rescaling.
- Fee-market conditions (Stellar's flat-fee resource metering is
  more stable than gas-priced chains, but fee bumps occur at
  protocol upgrades) are absorbed into `stroops` and
  `usd_at_anchor_date` and are not separately reported.
- The EF KZG ceremony transcript is hosted at
  `ceremony.ethereum.org` and a GitHub mirror; both are subject to
  link rot. Pin a stable archive (an IPFS CID is recommended) at
  submission time and record it in
  `srs.transcript_sha256`'s sibling field.
