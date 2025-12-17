#!/usr/bin/env bash
#
# rbr cs
#
# Non-AI cluster summary.
# Delegates to the existing cluster-summary.sh engine.
#

set -euo pipefail

# ---------------------------------------------------------
# Locate rbr root
# ---------------------------------------------------------
RBR_ROOT="${RBR_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

SUMMARY_SCRIPT="$RBR_ROOT/data/cluster-summary.sh"

# ---------------------------------------------------------
# Validate
# ---------------------------------------------------------
if [[ ! -f "$SUMMARY_SCRIPT" ]]; then
  echo "❌ cluster-summary.sh not found at:"
  echo "   $SUMMARY_SCRIPT"
  exit 1
fi

# ---------------------------------------------------------
# Run summary
# ---------------------------------------------------------
echo "🔹 Generating Basic Text Summary (using cluster-summary.sh)"
echo

# Always run in current directory (bundle root)
exec bash "$SUMMARY_SCRIPT" .

