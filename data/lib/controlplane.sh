#!/usr/bin/env bash
# controlplane.sh – API server, etcd, and control plane configuration summary

hdr "CONTROL PLANE CONFIGURATION"

SERVICE_FILE=""
NODE_ROLE="Unknown"

########################################
# 1. Detect service file & node role
########################################

case "$K8S_DISTRO" in
  rke2)
    if [[ -f "$ROOT/rke2/rke2-server.service" ]]; then
      SERVICE_FILE="$ROOT/rke2/rke2-server.service"
      NODE_ROLE="Control Plane (Server)"
    elif [[ -f "$ROOT/rke2/rke2-agent.service" ]]; then
      SERVICE_FILE="$ROOT/rke2/rke2-agent.service"
      NODE_ROLE="Worker (Agent)"
    fi
    ;;
  k3s)
    if [[ -f "$ROOT/k3s/k3s.service" ]]; then
      SERVICE_FILE="$ROOT/k3s/k3s.service"
      if safe_grep -q '\bserver\b' "$SERVICE_FILE"; then
        NODE_ROLE="Control Plane (Server)"
      elif safe_grep -q '\bagent\b' "$SERVICE_FILE"; then
        NODE_ROLE="Worker (Agent)"
      else
        NODE_ROLE="Control Plane (Server)"  # logs-collector style units often omit mode
      fi
    fi
    ;;
  kubeadm)
    # kubeadm bundles may not include kube-apiserver service explicitly.
    # We still try to locate a kubelet or apiserver unit, but keep this generic.
    if [[ -f "$ROOT/kubeadm/kube-apiserver.service" ]]; then
      SERVICE_FILE="$ROOT/kubeadm/kube-apiserver.service"
      NODE_ROLE="Control Plane (Server)"
    fi
    ;;
esac

log "Node Role (from service)" "$NODE_ROLE"

########################################
# 2. Parse config.yaml (rke2/k3s/kubeadm) – external vs embedded ETCD
########################################

CONFIG_FILE="$ROOT/$K8S_DISTRO/config.yaml"
EXT_ETCD="No (Embedded/Default DB)"
ETCD_DETAIL_LINE=""

if [[ -f "$CONFIG_FILE" ]]; then
  # rke2/k3s use datastore-* fields for external DB (etcd, MySQL, Postgres, etcd proxy)
  if grep -q 'datastore-endpoint' "$CONFIG_FILE" 2>/dev/null; then
    EXT_ETCD="Yes (External datastore)"
    ETCD_DETAIL_LINE="$(
      grep -E 'datastore-endpoint|datastore-cafile|datastore-certfile|datastore-keyfile' \
        "$CONFIG_FILE" 2>/dev/null | sed 's/^[[:space:]]*//'
    )"
  fi
fi

log "External Etcd/DB" "$EXT_ETCD"
if [[ -n "$ETCD_DETAIL_LINE" ]]; then
  # flattened for single-line readability
  log "  Datastore Fields" "$(echo "$ETCD_DETAIL_LINE" | tr '\n' ' ')"
fi

########################################
# 3. Key install arguments (sanitised)
########################################

INSTALL_ARGS="N/A"

if [[ -n "$SERVICE_FILE" && -f "$SERVICE_FILE" ]]; then
  INSTALL_ARGS="$(
    grep 'ExecStart' "$SERVICE_FILE" 2>/dev/null |
    # drop everything before the binary (k3s/rke2)
    sed -E 's/.*(k3s|rke2)[^[:space:]]*//;' |
    # redact values to avoid leaking tokens/paths:
    # --flag value  →  --flag [REDACTED]
    sed -E 's/(\s--[^=[:space:]]+)[[:space:]]+([^"-][^[:space:]]*)/\1 [REDACTED]/g' |
    # compact whitespace
    tr '\n' ' ' | sed 's/[[:space:]]\+/ /g'
  )"
  [[ -z "$INSTALL_ARGS" ]] && INSTALL_ARGS="N/A"
fi

log "Key Install Args" "$INSTALL_ARGS"

########################################
# 4. Embedded etcd health (if present)
########################################

ETCD_HEALTH="N/A"
ENDPOINT_HEALTH_FILE="$ROOT/etcd/endpointhealth"

if [[ -f "$ENDPOINT_HEALTH_FILE" ]]; then
  HEALTH_COUNT="$(grep -c 'health' "$ENDPOINT_HEALTH_FILE" 2>/dev/null || echo 0)"
  UNHEALTH_COUNT="$(grep -c 'unhealth' "$ENDPOINT_HEALTH_FILE" 2>/dev/null || echo 0)"

  HEALTH_COUNT="$(int_or_zero "$HEALTH_COUNT")"
  UNHEALTH_COUNT="$(int_or_zero "$UNHEALTH_COUNT")"

  if (( UNHEALTH_COUNT > 0 )); then
    ETCD_HEALTH="CRITICAL: ${UNHEALTH_COUNT} unhealthy member(s)"
  elif (( HEALTH_COUNT > 0 )); then
    ETCD_HEALTH="Healthy (${HEALTH_COUNT} member(s))"
  else
    ETCD_HEALTH="Unknown (no explicit health markers)"
  fi
fi

log "Embedded Etcd Health" "$ETCD_HEALTH"

########################################
# 5. RKE2 S3 ETCD backup hints (if logs present)
########################################

S3_BACKUP_STATUS="N/A"

if [[ "$K8S_DISTRO" = "rke2" ]]; then
  RKE2_SERVER_LOG="$ROOT/journald/rke2-server"

  if [[ -f "$RKE2_SERVER_LOG" ]]; then
    S3_BACKUP_STATUS="$(
      safe_grep 'Reusing cached S3 client for endpoint' "$RKE2_SERVER_LOG" | \
      tail -n1 | \
      sed -E 's/.*endpoint="([^"]+)".*bucket="([^"]+)".*folder="([^"]+)".*/S3 Backup: bucket \2\/\3 @ \1/'
    )"
    [[ -z "$S3_BACKUP_STATUS" ]] && S3_BACKUP_STATUS="Not detected in logs"
  else
    S3_BACKUP_STATUS="Logs not present in bundle"
  fi
else
  S3_BACKUP_STATUS="Not applicable"
fi

log "S3 Etcd Backup (RKE2)" "$S3_BACKUP_STATUS"

########################################
# 6. API server certificate presence
########################################

API_CERT_STATUS="Not found in bundle"

case "$K8S_DISTRO" in
  rke2)
    if [[ -f "$ROOT/rke2/certs/server/server.crt" ]]; then
      API_CERT_STATUS="Present (expiry not parsed from bundle)"
    fi
    ;;
  k3s)
    if [[ -f "$ROOT/k3s/certs/server/kube-apiserver.crt" ]]; then
      API_CERT_STATUS="Present (expiry not parsed from bundle)"
    fi
    ;;
  kubeadm)
    # very bundle-dependent; we just look in a few common places:
    if [[ -f "$ROOT/kubeadm/pki/apiserver.crt" ]]; then
      API_CERT_STATUS="Present (expiry not parsed from bundle)"
    fi
    ;;
esac

log "API Server Cert" "$API_CERT_STATUS"

echo ""
