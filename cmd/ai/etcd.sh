#!/usr/bin/env bash
# Collect etcd context ONLY (no AI, no python)

set -euo pipefail

# Always use absolute rbr path
RBR_BIN="$RBR_ROOT/bin/rbr"

ETCD_JSON="$("$RBR_BIN" etcd 2>/dev/null || true)"

# If empty or unsupported (k3s)
if [[ -z "$ETCD_JSON" ]]; then
  echo '    "etcd": { "note": "etcd not present or embedded (k3s)" }'
  exit 0
fi

# Print valid JSON (already JSON from data/lib/etcd.sh)
echo "    \"etcd\": $ETCD_JSON"

