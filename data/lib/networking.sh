#!/usr/bin/env bash
# networking.sh – CNI, runtime, and networking summary from bundle

hdr "CNI & NETWORKING"

PODS_FILE="$KUBECTL_DIR/pods"
IPLINK_FILE="$NETWORK_DIR/iplinkshow"
IPTABLES_FILE="$NETWORK_DIR/iptables"
NFT_FILE="$NETWORK_DIR/nft_ruleset"
IPADDR_FILE="$NETWORK_DIR/ipaddr"
CONFIG_FILE="$ROOT/$K8S_DISTRO/config.yaml"

CNI="UNKNOWN"
CNI_POD_PATTERN=""
CNI_PODS_STATUS="Unknown"
RUNTIME="N/A"
KPROXY_MODE="Unknown"
POD_CIDR="N/A"
SERVICE_CIDR="N/A"
IP_STACK="Unknown"

########################################
# 1. CNI DETECTION
########################################

# Primary POD-based detection
CNI_DETECT_LIST="
Calico:calico-node
Cilium:cilium-agent
Canal:canal
Flannel:kube-flannel
WeaveNet:weave-net
KubeRouter:kube-router
"

if [[ -f "$PODS_FILE" ]]; then
  for entry in $CNI_DETECT_LIST; do
    NAME="${entry%%:*}"
    PATTERN="${entry#*:}"

    if grep -qi "$PATTERN" "$PODS_FILE" 2>/dev/null; then
      CNI="$NAME"
      CNI_POD_PATTERN="$PATTERN"
      break
    fi
  done
fi

# Fallback 1: ip link patterns
if [[ "$CNI" == "UNKNOWN" && -f "$IPLINK_FILE" ]]; then
  if grep -qE '^[0-9]+: cali' "$IPLINK_FILE" 2>/dev/null; then
    CNI="Calico (via iplink)"
    CNI_POD_PATTERN="cali"
  elif grep -qE '^[0-9]+: cilium' "$IPLINK_FILE" 2>/dev/null; then
    CNI="Cilium (via iplink)"
    CNI_POD_PATTERN="cilium"
  elif grep -qE '^[0-9]+: weave' "$IPLINK_FILE" 2>/dev/null; then
    CNI="Weave (via iplink)"
    CNI_POD_PATTERN="weave"
  elif grep -qE '^[0-9]+: flannel' "$IPLINK_FILE" 2>/dev/null; then
    CNI="Flannel (via iplink)"
    CNI_POD_PATTERN="flannel"
  fi
fi

# Fallback 2: iptables patterns
if [[ "$CNI" == "UNKNOWN" && -f "$IPTABLES_FILE" ]]; then
  if grep -qi 'cali-' "$IPTABLES_FILE" 2>/dev/null; then
    CNI="Calico (via iptables)"
    CNI_POD_PATTERN="cali"
  elif grep -qi 'WEAVE' "$IPTABLES_FILE" 2>/dev/null; then
    CNI="Weave (via iptables)"
    CNI_POD_PATTERN="weave"
  elif grep -qi 'flannel' "$IPTABLES_FILE" 2>/dev/null; then
    CNI="Flannel (via iptables)"
    CNI_POD_PATTERN="flannel"
  fi
fi

# Fallback 3: K3s default
if [[ "$CNI" == "UNKNOWN" && "$K8S_DISTRO" = "k3s" ]]; then
  CNI="Flannel (K3s default)"
  CNI_POD_PATTERN="kube-flannel"
fi

########################################
# 2. Container Runtime (crictl info)
########################################

if [[ -f "$CRICTL_DIR/info" ]]; then
  RUNTIME="$(grep -m1 'RuntimeName' "$CRICTL_DIR/info" 2>/dev/null | awk -F\" '{print $4}')"
  [[ -z "$RUNTIME" ]] && RUNTIME="N/A"
fi

########################################
# 3. CNI POD READINESS STATUS
########################################

if [[ -n "$CNI_POD_PATTERN" && -f "$PODS_FILE" ]]; then
  CNI_TOKEN_LIST="$(
    grep -i "$CNI_POD_PATTERN" "$PODS_FILE" 2>/dev/null |
    awk '{
      for(i=1;i<=NF;i++){
        if($i ~ /^[0-9]+\/[0-9]+$/){ print $i; break }
      }
    }'
  )"

  TOTAL_READY=0
  TOTAL_EXPECTED=0

  for token in $CNI_TOKEN_LIST; do
    r="${token%/*}"
    e="${token#*/}"
    r_int="$(int_or_zero "$r")"
    e_int="$(int_or_zero "$e")"
    TOTAL_READY=$(( TOTAL_READY + r_int ))
    TOTAL_EXPECTED=$(( TOTAL_EXPECTED + e_int ))
  done

  if (( TOTAL_EXPECTED == 0 )); then
    CNI_PODS_STATUS="WARNING: No CNI pods detected (pattern '$CNI_POD_PATTERN')"
  elif (( TOTAL_READY == TOTAL_EXPECTED )); then
    CNI_PODS_STATUS="Ready (${TOTAL_READY}/${TOTAL_EXPECTED})"
  else
    CNI_PODS_STATUS="CRITICAL: Not All Ready (${TOTAL_READY}/${TOTAL_EXPECTED})"
  fi

elif [[ -f "$PODS_FILE" ]]; then
  CNI_PODS_STATUS="No known CNI pods detected"
else
  CNI_PODS_STATUS="Data missing (kubectl pods not collected)"
fi

########################################
# 4. Kube-proxy Mode (heuristic)
########################################

# Very coarse heuristic:
# - If iptables has KUBE-SERVICES → iptables-based kube-proxy
# - If nft_ruleset has kube-services → nftables-based kube-proxy
if [[ -f "$IPTABLES_FILE" ]] && grep -q 'KUBE-SERVICES' "$IPTABLES_FILE" 2>/dev/null; then
  KPROXY_MODE="iptables (heuristic)"
elif [[ -f "$NFT_FILE" ]] && grep -qi 'kube-services' "$NFT_FILE" 2>/dev/null; then
  KPROXY_MODE="nftables (heuristic)"
fi

########################################
# 5. Pod/Service CIDR & Dual-stack
########################################

# Try from k3s/rke2 config.yaml first
if [[ -f "$CONFIG_FILE" ]]; then
  POD_CIDR_RAW="$(grep -E '^[[:space:]]*cluster-cidr' "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d':' -f2-)"
  SERVICE_CIDR_RAW="$(grep -E '^[[:space:]]*service-cidr' "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d':' -f2-)"

  POD_CIDR="$(trim "$POD_CIDR_RAW")"
  SERVICE_CIDR="$(trim "$SERVICE_CIDR_RAW")"

  [[ -z "$POD_CIDR" ]] && POD_CIDR="N/A"
  [[ -z "$SERVICE_CIDR" ]] && SERVICE_CIDR="N/A"
fi

# Detect IP stack (IPv4 / IPv6 / Dual)
has_v4=0
has_v6=0

CIDR_SOURCE="$(printf '%s %s' "$POD_CIDR" "$SERVICE_CIDR" | tr ',' ' ')"

for tok in $CIDR_SOURCE; do
  case "$tok" in
    *.*/*) has_v4=1 ;;
    *:*/?*|*:*/*) has_v6=1 ;;  # crude match: has ':' and '/'
  esac
done

# Fallback: look at ipaddr if CIDRs are N/A
if [[ "$POD_CIDR" = "N/A" && "$SERVICE_CIDR" = "N/A" && -f "$IPADDR_FILE" ]]; then
  if grep -q 'inet ' "$IPADDR_FILE" 2>/dev/null; then
    has_v4=1
  fi
  if grep -q 'inet6 ' "$IPADDR_FILE" 2>/dev/null; then
    has_v6=1
  fi
fi

if (( has_v4 == 1 && has_v6 == 1 )); then
  IP_STACK="Dual-stack (IPv4 + IPv6)"
elif (( has_v4 == 1 )); then
  IP_STACK="IPv4 only"
elif (( has_v6 == 1 )); then
  IP_STACK="IPv6 only"
else
  IP_STACK="Unknown"
fi

########################################
# 6. Print summary
########################################

log "CNI Detected"        "**$CNI**"
log "CNI Pod Status"      "$CNI_PODS_STATUS"
log "Container Runtime"   "$RUNTIME"
log "Kube-Proxy Mode"     "$KPROXY_MODE"
log "Pod CIDR(s)"         "$POD_CIDR"
log "Service CIDR(s)"     "$SERVICE_CIDR"
log "IP Stack"            "$IP_STACK"

echo ""
