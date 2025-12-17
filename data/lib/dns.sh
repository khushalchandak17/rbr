#!/usr/bin/env bash
# dns.sh – Universal DNS / CoreDNS diagnostics (v1.0)

set -euo pipefail

########################################
# Bootstrap
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/utils.sh" ]] && source "$SCRIPT_DIR/utils.sh" || true

# Fallbacks (standalone-safe)
if ! declare -F hdr >/dev/null; then
  hdr() {
    echo ""
    echo "==============================================="
    printf " 📌 %s\n" "$1"
    echo "==============================================="
  }
fi

if ! declare -F log >/dev/null; then
  log() {
    printf "  %-28s %s\n" "$1:" "$2"
  }
fi

safe_grep() { [[ -f "$2" ]] && grep -E "$1" "$2" || true; }
count_matches() { [[ -f "$2" ]] && grep -Ec "$1" "$2" || echo 0; }

########################################
# Header
########################################

hdr "DNS / COREDNS SUMMARY"

########################################
# Detect distro & paths
########################################

DISTRO=unknown
KUBECTL_DIR=""
PODLOGS_DIR=""
CONFIG_FILE=""

if [[ -d rke2/kubectl ]]; then
  DISTRO=rke2
  KUBECTL_DIR=rke2/kubectl
  PODLOGS_DIR=rke2/podlogs
  CONFIG_FILE=rke2/50-rancher.yaml
elif [[ -d k3s/kubectl ]]; then
  DISTRO=k3s
  KUBECTL_DIR=k3s/kubectl
  PODLOGS_DIR=k3s/podlogs
fi

PODS_FILE="$KUBECTL_DIR/pods"
SVC_FILE="$KUBECTL_DIR/svc"
CM_FILE="$KUBECTL_DIR/cm"
EVENTS_FILE="$KUBECTL_DIR/events"
VERSION_FILE="$KUBECTL_DIR/version"

########################################
# Basic info
########################################

K8S_VERSION="$(safe_grep 'Server Version:' "$VERSION_FILE" | head -n1 || echo unknown)"
CLUSTER_DNS_IP=unknown

if [[ "$DISTRO" == "rke2" && -f "$CONFIG_FILE" ]]; then
  CLUSTER_DNS_IP="$(grep -E 'cluster-dns|cluster_dns' "$CONFIG_FILE" \
    | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/' \
    | head -n1 || true)"
fi
[[ -n "${CLUSTER_DNS_IP:-}" ]] || CLUSTER_DNS_IP=unknown

log "Distro" "$DISTRO"
log "K8s Version" "${K8S_VERSION:-unknown}"
log "Cluster DNS IP" "$CLUSTER_DNS_IP"
echo ""

########################################
# CoreDNS presence
########################################

COREDNS_PODS="$(safe_grep 'coredns' "$PODS_FILE")"
COREDNS_PRESENT=no
[[ -n "$COREDNS_PODS" ]] && COREDNS_PRESENT=yes

SVC_KUBE_DNS_COUNT="$(count_matches '(^|[[:space:]])kube-dns([[:space:]]|$)' "$SVC_FILE")"
SVC_COREDNS_COUNT="$(count_matches '(^|[[:space:]])coredns([[:space:]]|$)' "$SVC_FILE")"
SVC_PRESENT=no
(( SVC_KUBE_DNS_COUNT + SVC_COREDNS_COUNT > 0 )) && SVC_PRESENT=yes

CM_RKE2_COUNT="$(count_matches '(^|[[:space:]])rke2-coredns([[:space:]]|$)' "$CM_FILE")"
CM_COREDNS_COUNT="$(count_matches '(^|[[:space:]])coredns([[:space:]]|$)' "$CM_FILE")"
CM_PRESENT=no
(( CM_RKE2_COUNT + CM_COREDNS_COUNT > 0 )) && CM_PRESENT=yes

log "CoreDNS pods" "$COREDNS_PRESENT"
log "DNS service" "$SVC_PRESENT (kube-dns:$SVC_KUBE_DNS_COUNT, coredns:$SVC_COREDNS_COUNT)"
log "CoreDNS config" "$CM_PRESENT (rke2-coredns:$CM_RKE2_COUNT, coredns:$CM_COREDNS_COUNT)"

########################################
# Pod health
########################################

RUNNING_COUNT=0
NOT_READY_COUNT=0
RESTART_COUNT=0

if [[ -f "$PODS_FILE" ]]; then
  RUNNING_COUNT="$(safe_grep 'coredns' "$PODS_FILE" | grep -c ' Running ' || echo 0)"
  NOT_READY_COUNT="$(safe_grep 'coredns' "$PODS_FILE" | grep -Evc ' Running ' || echo 0)"
  RESTART_COUNT="$(safe_grep 'coredns' "$PODS_FILE" | grep -Ec '\([0-9]+' || echo 0)"
fi

log "CoreDNS Running" "$RUNNING_COUNT"
log "CoreDNS NotRunning" "$NOT_READY_COUNT"
log "CoreDNS Restarted" "$RESTART_COUNT"
echo ""

########################################
# Version (best effort)
########################################

DNS_VERSION=unknown
if [[ -n "$COREDNS_PODS" ]]; then
  DNS_VERSION="$(echo "$COREDNS_PODS" | grep -oE 'coredns:[^ ]+' | head -n1 | sed 's/coredns://' || true)"
fi
log "CoreDNS Version" "$DNS_VERSION"
echo ""

########################################
# Events
########################################

EVENT_KEYWORDS='coredns|kube-dns|dns|SERVFAIL|NXDOMAIN|timeout|no route|unreachable|iptables|conntrack'
RECENT_EVENTS="$(safe_grep "$EVENT_KEYWORDS" "$EVENTS_FILE" | tail -n 10 || true)"

echo "Recent DNS/network events:"
if [[ -n "$RECENT_EVENTS" ]]; then
  echo "$RECENT_EVENTS" | sed 's/^/  /'
else
  echo "  none"
fi
echo ""

########################################
# Logs (portable)
########################################

echo "CoreDNS logs (last 10 lines each, best-effort):"

if [[ -d "$PODLOGS_DIR" ]]; then
  for f in $(ls "$PODLOGS_DIR" 2>/dev/null | grep -Ei 'coredns|kube-dns' || true); do
    echo ""
    echo "---- $f ----"
    tail -n 10 "$PODLOGS_DIR/$f" 2>/dev/null || echo "  (unable to read)"
  done
else
  echo "  podlogs directory not found"
fi

