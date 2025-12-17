#!/usr/bin/env bash
#
# rbr ai cs (SAFE MODE)
#
# Shell collects cluster summary
# Gemini ONLY explains provided data
#

set -euo pipefail

# ---------------------------------------------------------
# Detect distro
# ---------------------------------------------------------
if [[ -d k3s ]]; then
  DISTRO="k3s"
elif [[ -d rke2 ]]; then
  DISTRO="rke2"
else
  echo "❌ Not inside a k3s or rke2 support bundle"
  exit 1
fi

TMP_CONTEXT="$(mktemp)"
trap 'rm -f "$TMP_CONTEXT"' EXIT

# ---------------------------------------------------------
# Collect cluster summary (shell side)
# ---------------------------------------------------------
{
  echo "=== CLUSTER SUMMARY ==="
  echo

  # Nodes
  if [[ -f "$DISTRO/kubectl/nodes" ]]; then
    echo "--- Nodes ---"
    cat "$DISTRO/kubectl/nodes"
    echo
  fi

  # Pods
  if [[ -f "$DISTRO/kubectl/pods" ]]; then
    echo "--- Pods ---"
    cat "$DISTRO/kubectl/pods"
    echo
  fi

  # Events (limit)
  if [[ -f "$DISTRO/kubectl/events" ]]; then
    echo "--- Events (last 50 lines) ---"
    tail -n 50 "$DISTRO/kubectl/events"
    echo
  fi
} > "$TMP_CONTEXT"

# ---------------------------------------------------------
# Gemini: explanation ONLY
# ---------------------------------------------------------
GEMINI_CMD="${GEMINI_CMD:-gemini}"

PROMPT=$(cat <<'EOF'
You are given a Kubernetes cluster summary extracted from a support bundle.

Your task:
1. Identify critical cluster-wide issues
2. Highlight the most unstable components
3. Explain likely root causes
4. Suggest high-level next actions

Rules:
- DO NOT read files
- DO NOT list directories
- DO NOT run commands
- DO NOT assume anything outside the given data
- Base your answer ONLY on the provided context
EOF
)

exec "$GEMINI_CMD" \
  --output-format text \
  -p "$PROMPT" \
  < "$TMP_CONTEXT"

