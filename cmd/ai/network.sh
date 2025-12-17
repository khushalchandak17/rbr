#!/usr/bin/env bash
# cmd/ai/network.sh – AI-powered network diagnosis (safe & bounded)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$ROOT_DIR/data/lib"

NETWORK_SUMMARY="$LIB_DIR/network.sh"

# ---------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------
if [[ ! -f "$NETWORK_SUMMARY" ]]; then
  echo "❌ network summary script not found: $NETWORK_SUMMARY" >&2
  exit 1
fi

if [[ ! -x "$NETWORK_SUMMARY" ]]; then
  echo "❌ network summary script is not executable" >&2
  echo "👉 run: chmod +x $NETWORK_SUMMARY" >&2
  exit 1
fi

# ---------------------------------------------------------
# Step 1: Run deterministic network summary
# ---------------------------------------------------------
echo "🔹 Collecting network diagnostics from bundle..."
NETWORK_OUTPUT="$("$NETWORK_SUMMARY")"

echo "$NETWORK_OUTPUT"

# ---------------------------------------------------------
# Step 2: Hand off to Gemini (bounded, explicit)
# ---------------------------------------------------------
echo ""
echo "🔹 Invoking AI network diagnosis..."

gemini \
  --approval-mode yolo \
  --allowed-mcp-server-names test_server \
  --allowed-tools auto_diagnose \
  --output-format text \
  "You are diagnosing Kubernetes networking issues.

Here is the cluster network summary:

$NETWORK_OUTPUT

Explain:
- CNI health
- kube-proxy implications
- DNS readiness
- likely failure modes (if any)

DO NOT run commands.
DO NOT read files.
ONLY analyze the summary."

