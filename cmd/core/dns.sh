#!/usr/bin/env bash
#
# cmd/core/dns.sh
# Core (non-AI) DNS / CoreDNS summary
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB_DIR="$ROOT_DIR/data/lib"

exec "$LIB_DIR/dns.sh"

