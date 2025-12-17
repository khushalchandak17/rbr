#!/usr/bin/env bash
#
# rbr logs <pod> [--previous]
#
# Behaviour:
# - Reads pod logs from extracted bundle
# - Supports k3s and rke2
# - Matches namespace-podname format
# - Supports --previous like kubectl
#

set -euo pipefail

# ---------------------------------------------------------
# Args
# ---------------------------------------------------------
POD="${1:-}"
FLAG="${2:-}"

if [[ -z "$POD" ]]; then
  echo "Usage: rbr logs <pod-name> [--previous]"
  exit 1
fi

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

LOG_DIR="$DISTRO/podlogs"

if [[ ! -d "$LOG_DIR" ]]; then
  echo "❌ podlogs directory not found: $LOG_DIR"
  exit 1
fi

# ---------------------------------------------------------
# Build match pattern
# ---------------------------------------------------------
if [[ "$FLAG" == "--previous" ]]; then
  MATCH_PATTERN="$POD-previous$"
else
  MATCH_PATTERN="$POD$"
fi

# ---------------------------------------------------------
# Find matching logs
# ---------------------------------------------------------
MATCHES=$(ls "$LOG_DIR" | grep -E "$MATCH_PATTERN" || true)

if [[ -z "$MATCHES" ]]; then
  echo "❌ No logs found for pod '$POD'"
  echo "Hint: try 'rbr logs <pod> --previous'"
  exit 1
fi

# ---------------------------------------------------------
# Print logs
# ---------------------------------------------------------
for LOG_FILE in $MATCHES; do
  echo
  echo "===== $LOG_FILE ====="
  echo
  cat "$LOG_DIR/$LOG_FILE"
done

