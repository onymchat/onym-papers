#!/usr/bin/env bash
# C1 benchmark harness — Stellar + BLS12-381 + Groth16 + Poseidon,
# five-contract deployment.
#
# Iterates over the five contracts, measures prover wall-clock and
# Soroban verifier resource cost per contract, and writes
# results.json (schema v1) consumed by the §4 tables.
#
# Run from this directory:  bash run.sh
# Or via the paper Makefile: make benchmarks

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/results.json"
ANCHOR_DATE="$(date -u +%Y-%m-%d)"

# ─── Contract slots ──────────────────────────────────────────────────
# Fill these in before running. Slot order is fixed by methodology.md;
# see that file for the relation each slot is expected to implement.
#
# Each entry is "<slot_key>:<contract_name>:<path_to_contract_workdir>".
# The path is where this script invokes the per-contract proving and
# deployment commands; the contract_name is what gets written into the
# results.json `contract_name` field.
CONTRACTS=(
  "contract_1:TODO:TODO/path/to/contract_1"
  "contract_2:TODO:TODO/path/to/contract_2"
  "contract_3:TODO:TODO/path/to/contract_3"
  "contract_4:TODO:TODO/path/to/contract_4"
  "contract_5:TODO:TODO/path/to/contract_5"
)

# ─── Pinning fields ──────────────────────────────────────────────────
# Filled at run time; kept editable here so reviewers re-running the
# harness on different hardware / software can record their setup.
HARDWARE_CPU="TODO"
HARDWARE_RAM="TODO"
HARDWARE_THREADS_BASELINE=1

SOROBAN_HOST_VERSION="TODO"
STELLAR_CORE_VERSION="TODO"
SOROBAN_CLI_VERSION="$(soroban --version 2>/dev/null | head -1 || echo TODO)"
PROVER_TOOLCHAIN_VERSION="TODO"
POSEIDON_PARAM_SET="TODO"

# ─── SRS provenance (EF KZG ceremony, supply-chain hashes) ───────────
# Fill from src/prover/srs/* in the contract source tree, or compute
# at run time. See methodology.md for the chain spec.
SRS_SOURCE="ethereum-foundation-kzg-ceremony-2023"
SRS_TRANSCRIPT_SHA256="TODO"      # upstream EF transcript JSON
SRS_EXTRACTED_BIN_SHA256="TODO"   # extracted bin form consumed by the prover
VK_SHA256_SMALL="TODO"
VK_SHA256_MEDIUM="TODO"
VK_SHA256_LARGE="TODO"

HARNESS_COMMIT="$(git -C "${HERE}" rev-parse HEAD 2>/dev/null || echo unknown)"

# XLM/USD spot rate fetcher. Override XLM_USD env var to skip the
# network call and use a fixed rate.
fetch_xlm_usd() {
  if [[ -n "${XLM_USD:-}" ]]; then
    echo "${XLM_USD}"
    return
  fi
  # TODO: replace with a pinned spot-rate source. The paper anchors
  # numbers to ANCHOR_DATE; using a live rate at run time is acceptable
  # for now but loses cross-run comparability.
  echo "TODO"
}

XLM_USD="$(fetch_xlm_usd)"

# ─── Per-contract measurement ────────────────────────────────────────
# Each measurement call below is a placeholder; replace with the actual
# proving and verification invocations for the contract under test.
# The contract harness should report:
#   - prover wall-clock in ms
#   - witness-construction wall-clock in ms (separately)
#   - verifying-key size in bytes
#   - proof size in bytes (192 expected for Groth16-on-BLS12-381)
#   - Soroban resource units consumed by a verify() call
#   - stroops billed by the verify() call
measure_contract() {
  local slot_key="$1"
  local contract_name="$2"
  local contract_path="$3"

  # TODO: replace these placeholders with real invocations.
  # The expected shape is that each command emits a single number on
  # stdout. The harness combines them into the results.json entry.
  local vk_size_bytes="TODO"
  local proof_size_bytes="TODO"
  local prover_wall_clock_ms="TODO"
  local prover_witness_construction_ms="TODO"
  local verifier_soroban_resource_units="TODO"
  local verifier_stroops="TODO"
  local verifier_usd="TODO"

  cat <<EOF
    "${slot_key}": {
      "contract_name": "${contract_name}",
      "contract_path": "${contract_path}",
      "vk_size_bytes": "${vk_size_bytes}",
      "proof_size_bytes": "${proof_size_bytes}",
      "prover": {
        "wall_clock_ms_total": "${prover_wall_clock_ms}",
        "witness_construction_ms": "${prover_witness_construction_ms}"
      },
      "verifier": {
        "soroban_resource_units": "${verifier_soroban_resource_units}",
        "stroops": "${verifier_stroops}",
        "usd_at_anchor_date": "${verifier_usd}"
      }
    }
EOF
}

# ─── Emit results.json ───────────────────────────────────────────────
{
  echo "{"
  echo "  \"schema_version\": 1,"
  echo "  \"anchor_date\": \"${ANCHOR_DATE}\","
  echo "  \"harness_commit\": \"${HARNESS_COMMIT}\","
  echo "  \"hardware\": {"
  echo "    \"cpu\": \"${HARDWARE_CPU}\","
  echo "    \"ram\": \"${HARDWARE_RAM}\","
  echo "    \"threads_baseline\": ${HARDWARE_THREADS_BASELINE}"
  echo "  },"
  echo "  \"software\": {"
  echo "    \"soroban_host_version\": \"${SOROBAN_HOST_VERSION}\","
  echo "    \"stellar_core_version\": \"${STELLAR_CORE_VERSION}\","
  echo "    \"soroban_cli_version\": \"${SOROBAN_CLI_VERSION}\","
  echo "    \"prover_toolchain_version\": \"${PROVER_TOOLCHAIN_VERSION}\","
  echo "    \"poseidon_param_set\": \"${POSEIDON_PARAM_SET}\""
  echo "  },"
  echo "  \"market\": {"
  echo "    \"xlm_usd\": \"${XLM_USD}\""
  echo "  },"
  echo "  \"srs\": {"
  echo "    \"source\": \"${SRS_SOURCE}\","
  echo "    \"transcript_sha256\": \"${SRS_TRANSCRIPT_SHA256}\","
  echo "    \"extracted_bin_sha256\": \"${SRS_EXTRACTED_BIN_SHA256}\","
  echo "    \"vk_sha256_small\": \"${VK_SHA256_SMALL}\","
  echo "    \"vk_sha256_medium\": \"${VK_SHA256_MEDIUM}\","
  echo "    \"vk_sha256_large\": \"${VK_SHA256_LARGE}\""
  echo "  },"
  echo "  \"c1\": {"

  first=1
  for entry in "${CONTRACTS[@]}"; do
    IFS=':' read -r slot_key contract_name contract_path <<< "${entry}"
    if [[ ${first} -eq 0 ]]; then
      echo "    ,"
    fi
    first=0
    measure_contract "${slot_key}" "${contract_name}" "${contract_path}" \
      | sed 's/^/    /'
  done

  echo "  },"
  echo "  \"aggregate\": {"
  echo "    \"comment\": \"TODO: derive p50/p95 over the five contracts after measure_contract is implemented.\","
  echo "    \"proof_size_bytes\": 192"
  echo "  }"
  echo "}"
} > "${OUT}"

echo "Wrote ${OUT}"
echo "Re-run 'make' from the paper root to regenerate the PDF with the updated table cells."
