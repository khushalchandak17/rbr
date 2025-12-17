#!/usr/bin/env bash
# workloads.sh – summarises workloads from the bundle
# NOTE: This module MUST NOT print headers. Headers are owned by cluster-summary.sh

########################################
# Ensure dependencies
########################################

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/core.sh"

########################################
# Ensure KUBECTL_DIR is set
########################################

if [[ -z "${KUBECTL_DIR:-}" ]]; then
  if [[ -d "k3s/kubectl" ]]; then
    KUBECTL_DIR="k3s/kubectl"
  elif [[ -d "rke2/kubectl" ]]; then
    KUBECTL_DIR="rke2/kubectl"
  else
    return 0
  fi
fi

########################################
# Files
########################################

PODS_FILE="$KUBECTL_DIR/pods"
DEPLOY_FILE="$KUBECTL_DIR/deployments"
DS_FILE="$KUBECTL_DIR/daemonsets"
STS_FILE="$KUBECTL_DIR/statefulsets"

########################################
# Helpers
########################################

count_non_header() {
  local file="$1"
  [[ ! -f "$file" ]] && echo 0 && return
  grep -vE '^(NAME|NAMESPACE)' "$file" | wc -l | awk '{print $1+0}'
}

to_int() {
  awk 'END { print ($1 ~ /^[0-9]+$/) ? $1 : 0 }'
}

########################################
# Pod counts
########################################

TOTAL_PODS="$(count_non_header "$PODS_FILE")"
RUNNING_PODS="$(grep -c ' Running ' "$PODS_FILE" 2>/dev/null | to_int)"
PENDING_PODS="$(grep -c ' Pending ' "$PODS_FILE" 2>/dev/null | to_int)"
FAILED_PODS="$(grep -c ' Failed ' "$PODS_FILE" 2>/dev/null | to_int)"
CRASH_PODS="$(grep -c 'CrashLoopBackOff' "$PODS_FILE" 2>/dev/null | to_int)"
IMAGE_ERR_PODS="$(grep -E 'ErrImagePull|ImagePullBackOff' "$PODS_FILE" 2>/dev/null | to_int)"

########################################
# Workload readiness
########################################

TOTAL_DEPLOYS="$(count_non_header "$DEPLOY_FILE")"
TOTAL_DAEMONSETS="$(count_non_header "$DS_FILE")"
TOTAL_STS="$(count_non_header "$STS_FILE")"

DEPLOY_NOT_READY="$(
  grep -vE '^(NAME|NAMESPACE)' "$DEPLOY_FILE" 2>/dev/null |
  awk '{for(i=1;i<=NF;i++) if($i~/^[0-9]+\/[0-9]+$/){split($i,a,"/"); if(a[1]!=a[2]){print; break}}}' |
  wc -l | to_int
)"

DS_NOT_READY="$(
  grep -vE '^(NAME|NAMESPACE)' "$DS_FILE" 2>/dev/null |
  awk '{for(i=1;i<=NF;i++) if($i~/^[0-9]+\/[0-9]+$/){split($i,a,"/"); if(a[1]!=a[2]){print; break}}}' |
  wc -l | to_int
)"

STS_NOT_READY="$(
  grep -vE '^(NAME|NAMESPACE)' "$STS_FILE" 2>/dev/null |
  awk '{for(i=1;i<=NF;i++) if($i~/^[0-9]+\/[0-9]+$/){split($i,a,"/"); if(a[1]!=a[2]){print; break}}}' |
  wc -l | to_int
)"

########################################
# Output (ONLY log calls)
########################################

log "Total Pods"          "$TOTAL_PODS"
log "Running Pods"        "$RUNNING_PODS"
log "Pending Pods"        "$PENDING_PODS"
log "Failed Pods"         "$FAILED_PODS"

if (( CRASH_PODS > 0 )); then
  log "CrashLoopBackOff"  "CRITICAL: $CRASH_PODS pod(s)"
else
  log "CrashLoopBackOff"  "None"
fi

if (( IMAGE_ERR_PODS > 0 )); then
  log "ImagePull Errors"  "CRITICAL: $IMAGE_ERR_PODS pod(s)"
else
  log "ImagePull Errors"  "None"
fi

log "Deployments"           "$TOTAL_DEPLOYS total"
log "Deployments NotReady"  "$DEPLOY_NOT_READY"
log "DaemonSets"            "$TOTAL_DAEMONSETS total"
log "DS NotReady"           "$DS_NOT_READY"
log "StatefulSets"          "$TOTAL_STS total"
log "STS NotReady"          "$STS_NOT_READY"