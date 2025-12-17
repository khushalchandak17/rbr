#!/usr/bin/env bash
#
# cmd/core/network.sh
# Core (non-AI) network summary
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$ROOT_DIR/data/lib"

exec "$LIB_DIR/network.sh"

