#!/usr/bin/env bash
#
# rbr ai pods
#
# AI diagnosis of pod health using:
# - kubectl/pods table
# - last 20 lines of pod logs
# - last 10 lines of previous logs (if any)
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

PODS_FILE="$DISTRO/kubectl/pods"
LOG_DIR="$DISTRO/podlogs"

[[ -f "$PODS_FILE" ]] || {
  echo "❌ pods file not found: $PODS_FILE"
  exit 1
}

# ---------------------------------------------------------
# Build diagnosis context
# ---------------------------------------------------------
TMP_CONTEXT="$(mktemp)"
trap 'rm -f "$TMP_CONTEXT"' EXIT

{
  echo "=== POD STATUS SUMMARY ==="
  echo
  cat "$PODS_FILE"
  echo
  echo "=== POD LOG SAMPLES (LIMITED) ==="
  echo
} >> "$TMP_CONTEXT"

# ---------------------------------------------------------
# Identify problematic pods
# ---------------------------------------------------------
tail -n +2 "$PODS_FILE" | while read -r NS NAME READY STATUS RESTARTS _; do
  # Normalize restart count
  RESTART_COUNT="$(echo "$RESTARTS" | awk '{print $1}')"

  IS_BAD=false
  [[ "$STATUS" != "Running" ]] && IS_BAD=true
  [[ "$STATUS" == "Running" && "$RESTART_COUNT" -gt 0 ]] && IS_BAD=true

  [[ "$IS_BAD" == false ]] && continue

  POD_KEY="${NS}-${NAME}"

  {
    echo
    echo "----- POD: $POD_KEY -----"
    echo "Status: $STATUS"
    echo "Restarts: $RESTART_COUNT"
    echo

    # Current logs (last 20 lines)
    if [[ -f "$LOG_DIR/$POD_KEY" ]]; then
      echo "[Last 20 lines - current logs]"
      tail -n 20 "$LOG_DIR/$POD_KEY"
    else
      echo "[No current logs found]"
    fi

    echo

    # Previous logs (last 10 lines)
    if [[ -f "$LOG_DIR/$POD_KEY-previous" ]]; then
      echo "[Last 10 lines - previous logs]"
      tail -n 10 "$LOG_DIR/$POD_KEY-previous"
    fi

  } >> "$TMP_CONTEXT"

done

# ---------------------------------------------------------
# Gemini execution
# ---------------------------------------------------------
GEMINI_CMD="${GEMINI_CMD:-gemini}"

PROMPT=$(cat <<'EOF'
You are diagnosing Kubernetes pod health from a support bundle.

You are given:
- A pods status table
- Limited pod log excerpts (last 20 current, last 10 previous)

Your task:
1. Group pods by failure type (CrashLoop, config error, image pull, dependency, etc)
2. Explain the most likely root cause for each group
3. Highlight the most critical pods first
4. Suggest concrete next actions (what to check or fix)

Rules:
- DO NOT read files
- DO NOT list directories
- DO NOT run commands
- Use ONLY the provided context
- Be concise and factual
EOF
)

exec "$GEMINI_CMD" \
  --approval-mode yolo \
  --allowed-mcp-server-names test_server \
  --allowed-tools auto_diagnose \
  --output-format text \
  -p "$PROMPT" \
  < "$TMP_CONTEXT"

