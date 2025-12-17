#!/usr/bin/env bash
# cmd/ai/dns.sh – AI DNS troubleshooting

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DNS_SUMMARY="$ROOT/data/lib/dns.sh"

echo "🔹 Collecting DNS diagnostics from bundle..."
set +e
"$DNS_SUMMARY"
RC=$?
set -e

if [[ "$RC" -eq 0 ]]; then
  echo "✅ DNS appears healthy — skipping AI analysis"
  exit 0
fi

echo "🔹 Invoking AI DNS diagnosis..."

SUMMARY="$("$DNS_SUMMARY" || true)"

gemini \
  --approval-mode yolo \
  --allowed-mcp-server-names test_server \
  --allowed-tools auto_diagnose \
  --output-format text \
  "
You are a Kubernetes DNS expert.

Given the following CoreDNS summary, diagnose ONLY real DNS failure scenarios.

Rules:
- IGNORE common CoreDNS warnings:
  * missing import globs
  * single i/o timeout
  * health plugin slow responses
- IGNORE normal autoscaler sync delays
- FOCUS on:
  * CoreDNS not running
  * DNS service missing
  * repeated upstream timeouts to same IP
  * SERVFAIL / REFUSED / NXDOMAIN storms
  * restart loops

Provide:
1. Root cause hypothesis
2. What is broken (cluster DNS vs upstream)
3. 3 concrete verification steps
4. 3 safe remediation steps

DNS SUMMARY:
$SUMMARY
"

