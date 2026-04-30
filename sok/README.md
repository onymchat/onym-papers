# SoK: Metadata-Hiding Group Registries with SNARK-Gated State Changes

LaTeX source for a Systematization of Knowledge paper surveying the
design space of metadata-hiding group registries with SNARK-gated state
changes. Targets a top-tier security venue (IEEE S&P, USENIX Security,
CCS, or FC); class file currently set to `IEEEtran` conference. Final
venue selected at the integration pass — the class-file swap is
mechanical.

## Design-space topology — where we are, where we're heading

```
                          SoK DESIGN-SPACE TOPOLOGY
                     (★ = where we are now, ▷ = aimed-at)


              PAST                   PRESENT                  FUTURE
            ─────────               ─────────                ─────────

         ┌─────────────┐        ┌─────────────┐          ┌─────────────┐
         │   C1-old    │        │    C1 ★     │          │     C7      │
         │             │        │             │          │             │
         │  Groth16    │ ──Δ──► │   PLONK     │ ──╳──►   │  Stellar +  │
         │  + per-     │        │   + KZG     │          │  Plonky3 +  │
         │  circuit    │ SNARK  │   + EF SRS  │ blocked  │     FRI     │
         │  MPC × 30   │ family │             │ on FRI   │             │
         │             │ swap + │  pairing-   │ host     │  hash-based │
         │ pairing-    │ SRS    │  based      │ functions│  PQ ★★      │
         │ based       │ reuse  │             │          │             │
         │             │        │             │          │  transparent│
         │ trapdoor:   │        │ trapdoor:   │          │  setup      │
         │ 1-of-N ×30  │        │ 1-of-141k×1 │          │             │
         └─────────────┘        └──────┬──────┘          └─────────────┘
            (deprecated)               │                  (post-quantum,
                                       │                   host-blocked,
                                       │                    Class b)
                              Class (a)│
                              anchor   │  trade Stellar
                              change   │  for PQ today
                                       ▼
                                ┌─────────────┐
                                │     C6      │
                                │             │
                                │ StarkNet +  │
                                │   STARK     │
                                │             │
                                │  hash-based │
                                │  PQ ★★      │
                                │  transparent│
                                │  setup      │
                                └─────────────┘


  THE SIX AXES (▷ marks the axis the next move changes):

    Anchor chain     Stellar ★ ═══════════════════════════════ Stellar
    SNARK system     PLONK ★   ═══════════════════════════════ PLONK
    Curve / hash     BLS12-381/Poseidon ★ ──────► Goldilocks/Poseidon2  ▷
    Trusted setup    Universal (EF KZG) ★ ──────► Transparent           ▷
    PQ stance        Pairing-based ★      ──────► Hash-based            ▷
    Verifier host    CAP-0059 + CAP-0075 ★──────► CAP-007x (FRI/NTT)    ▷
                                                            │
                                                            └─ blocking gap


  TRAPDOOR-TRUST POSTURE (the recent move's structural win):

    C1-old   ████████████████░░░░░░░░░░░░░░░░░░  1-of-N (small) × 30 ceremonies
    C1 ★    ████████████████████████████████████  1-of-141,000 × 1  (EF KZG)
    C7      ─── no trapdoor ────────────────────  transparent setup
                                                  (when host-unblocked)


  CHEAP-AND-PQ-AND-DECENTRALIZED CELL (§4.6):

       cheap?      PQ-ready?    decentralized-anchor?
        ✓           ─             ─              <- C1 ★ (here)
        ─           ✓             ─              <- C6 on StarkNet
        ✓           ✓             ─              <- C5 (mis-classified)
        ✓           ✓             ✓              <- empty (open problem)
        ✓           ✓             ─              <- C7 (host-blocked)
```

## Build

Requires `latexmk` and a TeX Live distribution with `IEEEtran.cls`,
`tikz`, `booktabs`, `tabularx`, `cleveref`, `microtype`.

```sh
make            # build main.pdf
make watch      # continuous rebuild (latexmk -pvc)
make clean      # remove aux files, keep PDF
make distclean  # remove all generated files including PDF
make benchmarks # re-run the C1 benchmark harness (5 contracts)
```

## Anonymization for double-blind submission

Edit `main.tex`:

```tex
\anonymousfalse  →  \anonymoustrue
```

This collapses the author block to "Anonymous Submission". Verify the
following before submitting:

- The `sep-onym` entry's `author` field in `references.bib` will need
  redaction at submission time.
- In-prose mentions of the C1 deployment use neutral phrasing
  ("the Stellar+BLS12-381+PLONK configuration", "the C1 row"); do a
  final pass for any remaining first-person references.

## Layout

| Path | Purpose |
|---|---|
| `main.tex`        | Entry point — class, packages, `\input` lines |
| `sections/`       | Eleven section files (00-abstract through 10-conclusion) |
| `figures/`        | TikZ source for Figures 1 (six-axis taxonomy) and 2 (migration DAG) |
| `tables/`         | Five comparison tables for §4 |
| `benchmarks/c1/`  | First-party measurement harness for the C1 row (5 Soroban contracts) |
| `references.bib`  | BibTeX |

## C1 measurement methodology

The C1 row in §4 is generated from a first-party harness at
`benchmarks/c1/`. The C1 configuration is
**Stellar + BLS12-381 + PLONK + Poseidon**, deployed as five
Soroban contracts (one policy per contract) whose ~thirty verifying
keys all derive from a single SRS reused from the
**Ethereum Foundation KZG Summoning Ceremony** (~141,000 contributors,
2022–2023; same SRS as Ethereum's EIP-4844 blob commitments).

`benchmarks/c1/methodology.md` documents the SRS provenance
hash-chain (transcript → extracted SRS bin → per-tier verifying keys →
contract WASM), what is and is not timed, hardware / software pinning,
and the `results.json` schema. The harness writes `results.json`;
LaTeX table cells consume it via generated `.tex` snippets so the
PDF stays in sync with measurements when the benchmark is re-run.

The five-contract slot table at the top of `methodology.md` has TODO
slots for contract names, paths, and SRS hash fields. Fill these
before running. See also the `CONTRACTS` array at the top of
`benchmarks/c1/run.sh`.

## Status

Sections drafted end-to-end (~17 pages including bibliography and
appendix; body content sits at ~14 pages, one over the IEEE S&P
13-page body limit — tighten §5.1 at submission time if S&P is the
final venue). Outstanding work tracked inline as TODO comments in
the source:

- §4 table cells marked TBD pending the C1 measurement-pass.
- A handful of `TODO §4 cite` slots in the cost table for C3, C4,
  C5, C6 — pin specific source URLs at the §4 measurement-pass
  refresh.
- Figures 1 and 2 are real TikZ but may want polish (axis-marker
  positions, DAG layout) once the contributing data is final.
- EF KZG ceremony bib entry has a TODO for a stable transcript URL
  / IPFS CID at submission time.
- For double-blind submission: flip `\anonymoustrue` and redact the
  `sep-onym` author field in `references.bib`.

The §9 cite-pass, the §3 dependency-chain analysis, and the
SNARK-family update from Groth16 + per-circuit MPC to PLONK + EF
KZG are all locked.
