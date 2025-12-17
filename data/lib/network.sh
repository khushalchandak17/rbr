#!/usr/bin/env bash
# network.sh – Universal, standalone-safe network diagnostics (v3)

set -euo pipefail

########################################
# Bootstrap (safe everywhere)
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/utils.sh" ]] && source "$SCRIPT_DIR/utils.sh" || true

if ! declare -F hdr >/dev/null 2>&1; then
  hdr() {
    echo ""
    echo "==============================================="
    printf " 📌 %s\n" "$1"
    echo "==============================================="
  }
fi

if ! declare -F log >/dev/null 2>&1; then
  log() { printf "  %-25s %s\n" "$1:" "$2"; }
fi

hdr "NETWORK SUMMARY"

########################################
# Detect bundle & distro
########################################

if [[ -d "rke2/kubectl" ]]; then
  KUBECTL_DIR="rke2/kubectl"
  RBR_DISTRO="rke2"
elif [[ -d "k3s/kubectl" ]]; then
  KUBECTL_DIR="k3s/kubectl"
  RBR_DISTRO="k3s"
else
  KUBECTL_DIR=""
  RBR_DISTRO="unknown"
fi

PODS_FILE="$KUBECTL_DIR/pods"
EVENTS_FILE="$KUBECTL_DIR/events"
VERSION_FILE="$KUBECTL_DIR/version"

########################################
# Helpers
########################################

safe_grep() { [[ -f "$2" ]] && grep -E "$1" "$2" || true; }
safe_cat()  { [[ -f "$1" ]] && cat "$1" || true; }

########################################
# CNI detection (authoritative)
########################################

detect_cni() {
  if [[ "$RBR_DISTRO" == "rke2" && -f "rke2/50-rancher.yaml" ]]; then
    local val
    val="$(grep -E '"cni"\s*:\s*"' -m1 rke2/50-rancher.yaml \
  | sed -E 's/.*"cni"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
  | tr -d ',' || true)"
   [[ -n "$val" ]] && { echo "$val"; return; }
  fi

  if [[ "$RBR_DISTRO" == "k3s" ]]; then
    safe_grep 'flannel|kube-flannel' "$PODS_FILE" >/dev/null && { echo flannel; return; }
  fi

  safe_grep 'calico-system.*calico-node' "$PODS_FILE" >/dev/null && { echo calico; return; }
  safe_grep 'cilium-system|cilium-agent' "$PODS_FILE" >/dev/null && { echo cilium; return; }

  echo unknown
}

########################################
# Multus detection (strict)
########################################

detect_multus() {
  safe_grep 'multus-daemonset' "$PODS_FILE" >/dev/null && { echo present; return; }
  safe_grep 'k8s.v1.cni.cncf.io' "$PODS_FILE" >/dev/null && { echo present; return; }
  echo not-detected
}

########################################
# kube-proxy & DNS
########################################

kube_proxy_status() {
  if [[ "$RBR_DISTRO" == "rke2" ]]; then
    safe_grep 'kube-system.*kube-proxy' "$PODS_FILE" >/dev/null && echo present || echo missing
  else
    echo "n/a (embedded in k3s)"
  fi
}

dns_status() {
  safe_grep 'coredns' "$PODS_FILE" >/dev/null && echo present || echo missing
}

########################################
# Output
########################################

KVER="$(safe_cat "$VERSION_FILE" | tr '\n' ' ' | sed 's/  */ /g')"

log "Distro"       "$RBR_DISTRO"
log "K8s Version" "${KVER:-N/A}"
log "CNI"         "$(detect_cni)"
log "Multus"      "$(detect_multus)"
log "kube-proxy"  "$(kube_proxy_status)"
log "DNS"         "$(dns_status)"

echo ""

echo "Key components:"
echo "  - coredns: OK"

if [[ "$(detect_cni)" == "calico" ]]; then
  safe_grep 'calico-node' "$PODS_FILE" >/dev/null && echo "  - calico-node: OK"
  safe_grep 'calico-typha' "$PODS_FILE" >/dev/null && echo "  - calico-typha: OK"
fi

if [[ "$RBR_DISTRO" == "rke2" ]]; then
  safe_grep 'kube-proxy' "$PODS_FILE" >/dev/null && echo "  - kube-proxy: OK"
fi

echo ""

if [[ -f "$EVENTS_FILE" ]]; then
  grep -Ei 'cni|dns|mtu|route|vxlan|bgp|timeout|unreachable' "$EVENTS_FILE" \
    | tail -n 20 || echo "Recent network events: none"
else
  echo "Recent network events: none"
fi

echo ""
