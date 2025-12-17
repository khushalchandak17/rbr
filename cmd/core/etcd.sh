#!/usr/bin/env bash
set -euo pipefail

LIB="$RBR_ROOT/data/lib/etcd.sh"

if [[ ! -x "$LIB" ]]; then
  echo "❌ etcd diagnostics not available in this bundle"
  exit 1
fi

exec "$LIB"

