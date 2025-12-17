#!/usr/bin/env bash
# data/lib/etcd.sh — deterministic etcd bundle inspection (v1.0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------
# Detect distro
# --------------------------------------------------
if [[ -d rke2/kubectl ]]; then
  DISTRO="rke2"
  BASE="rke2"
elif [[ -d k3s/kubectl ]]; then
  DISTRO="k3s"
  BASE="k3s"
else
  cat <<EOF
{ "error": "unknown kubernetes distro in bundle" }
EOF
  exit 0
fi

KUBECTL_DIR="$BASE/kubectl"
PODS_FILE="$KUBECTL_DIR/pods"
EVENTS_FILE="$KUBECTL_DIR/events"
PODLOGS_DIR="$BASE/podlogs"

# --------------------------------------------------
# Etcd pod detection (SAFE)
# --------------------------------------------------
ETCD_PODS="$(grep -E '(^|[[:space:]])etcd' "$PODS_FILE" 2>/dev/null || true)"
ETCD_COUNT="$(printf "%s\n" "$ETCD_PODS" | grep -c . || true)"

# --------------------------------------------------
# Restart count (SAFE)
# --------------------------------------------------
RESTARTS="$(printf "%s\n" "$ETCD_PODS" \
  | awk '{print $5}' \
  | grep -Eo '^[0-9]+' || true)"

TOTAL_RESTARTS=0
if [[ -n "$RESTARTS" ]]; then
  TOTAL_RESTARTS="$(printf "%s\n" "$RESTARTS" | awk '{s+=$1} END{print s}')"
fi

# --------------------------------------------------
# Events (SAFE)
# --------------------------------------------------
ETCD_EVENTS="$(grep -Ei 'etcd|raft|leader|quorum' "$EVENTS_FILE" 2>/dev/null | tail -n 10 || true)"

# --------------------------------------------------
# Logs (best effort, SAFE)
# --------------------------------------------------
LOG_SAMPLE=""
if [[ -d "$PODLOGS_DIR" ]]; then
  ETCD_LOG="$(ls "$PODLOGS_DIR" 2>/dev/null | grep -i etcd | head -n 1 || true)"
  if [[ -n "$ETCD_LOG" ]]; then
    LOG_SAMPLE="$(tail -n 20 "$PODLOGS_DIR/$ETCD_LOG" 2>/dev/null || true)"
  fi
fi

# --------------------------------------------------
# Emit JSON (ALWAYS)
# --------------------------------------------------
cat <<EOF
{
  "distro": "$DISTRO",
  "pods_present": $ETCD_COUNT,
  "pods_restarting": ${TOTAL_RESTARTS:-0},
  "recent_events": "$(printf "%s" "$ETCD_EVENTS" | tr '\n' ' ' | sed 's/"/'\''/g')",
  "log_sample": "$(printf "%s" "$LOG_SAMPLE" | tr '\n' ' ' | sed 's/"/'\''/g')"
}
EOF

