#!/usr/bin/env bash
#
# cmd/core/doctor.sh
# High-level cluster health check (non-AI)
#
# Runs:
#   - Cluster summary
#   - Network diagnostics
#   - DNS / CoreDNS diagnostics
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_DIR="$ROOT_DIR/cmd/core"

sep() {
  echo
  echo "=================================================="
  echo " 🩺 RBR DOCTOR — CLUSTER HEALTH CHECK"
  echo "=================================================="
  echo
}

run_step() {
  local name="$1"
  local script="$2"

  echo
  echo "🔹 $name"
  echo "--------------------------------------------------"

  if [[ -x "$script" ]]; then
    if ! "$script"; then
      echo "⚠️  $name reported issues"
    fi
  else
    echo "⚠️  Skipped ($script not found)"
  fi
}

sep

run_step "Cluster Summary" "$CORE_DIR/cs.sh"
run_step "Network Diagnostics" "$CORE_DIR/network.sh"
run_step "DNS / CoreDNS Diagnostics" "$CORE_DIR/dns.sh"

echo
echo "=================================================="
echo " ✅ Doctor run completed"
echo "=================================================="

