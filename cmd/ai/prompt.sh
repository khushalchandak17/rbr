#!/usr/bin/env bash
set -euo pipefail

QUESTION="${*:-}"
[[ -z "$QUESTION" ]] && {
  echo "❌ Missing prompt text"
  exit 1
}

BUNDLE_PATH="$(pwd)"

echo "🔹 Interpreting prompt:"
echo "   \"$QUESTION\""
echo ""

INTENT="generic"
TOOL="auto_diagnose"
CTX="{}"

echo "$QUESTION" | grep -iq "etcd"    && INTENT="etcd"
echo "$QUESTION" | grep -iq "dns"     && INTENT="dns"
echo "$QUESTION" | grep -iq "network" && INTENT="network"

case "$INTENT" in
  etcd)
    echo "🔹 Collecting etcd diagnostics from bundle..."
    CTX="$("$RBR_ROOT/bin/rbr" etcd)"
    ;;
  dns)
    echo "🔹 Collecting DNS diagnostics from bundle..."
    CTX="$("$RBR_ROOT/bin/rbr" dns)"
    ;;
  network)
    echo "🔹 Collecting network diagnostics from bundle..."
    CTX="$("$RBR_ROOT/bin/rbr" network)"
    ;;
esac

echo ""
echo "🔹 Invoking Gemini with context..."

gemini \
  --approval-mode yolo \
  --allowed-mcp-server-names test_server \
  --allowed-tools auto_diagnose \
  --output-format text \
  "QUESTION: $QUESTION

CONTEXT:
$CTX"

