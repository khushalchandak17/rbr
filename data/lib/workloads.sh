#!/usr/bin/env bash
# workloads.sh – summarises workloads from the bundle

hdr "WORKLOADS SUMMARY"

PODS_FILE="$KUBECTL_DIR/pods"
DEPLOY_FILE="$KUBECTL_DIR/deployments"
DS_FILE="$KUBECTL_DIR/daemonsets"
STS_FILE="$KUBECTL_DIR/statefulsets"

########################################
# HELPERS (using utils.sh functions)
########################################

count_non_header() {
  local file="$1"
  [[ ! -f "$file" ]] && echo 0 && return
  grep -vE '^(NAME|NAMESPACE)' "$file" | wc -l | awk '{print $1}'
}

########################################
# POD COUNTS + STATUS
########################################

TOTAL_PODS=0
RUNNING_PODS=0
PENDING_PODS=0
FAILED_PODS=0
CRASH_PODS=0
IMAGE_ERR_PODS=0

if [[ -f "$PODS_FILE" ]]; then
  TOTAL_PODS="$(count_non_header "$PODS_FILE")"

  RUNNING_PODS="$(grep -c ' Running ' "$PODS_FILE" 2>/dev/null || echo 0)"
  PENDING_PODS="$(grep -c ' Pending ' "$PODS_FILE" 2>/dev/null || echo 0)"
  FAILED_PODS="$(grep -c ' Failed ' "$PODS_FILE" 2>/dev/null || echo 0)"

  # CrashLoopBackOff detection (container-level)
  CRASH_PODS="$(grep -c 'CrashLoopBackOff' "$PODS_FILE" 2>/dev/null || echo 0)"

  # ImagePull errors
  IMAGE_ERR_PODS="$(grep -E 'ErrImagePull|ImagePullBackOff' -c "$PODS_FILE" 2>/dev/null || echo 0)"
else
  TOTAL_PODS="N/A"
fi

########################################
# DEPLOYMENTS / DAEMONSETS / STATEFULSETS
########################################

TOTAL_DEPLOYS="$(count_non_header "$DEPLOY_FILE")"
TOTAL_DAEMONSETS="$(count_non_header "$DS_FILE")"
TOTAL_STS="$(count_non_header "$STS_FILE")"

# Deployment readiness
DEPLOY_NOT_READY=0
if [[ -f "$DEPLOY_FILE" ]]; then
  DEPLOY_NOT_READY="$(
    grep -vE '^(NAME|NAMESPACE)' "$DEPLOY_FILE" |
    awk '{ for(i=1;i<=NF;i++){ if($i~/^[0-9]+\/[0-9]+$/){ if($i!=$i){ } } }
           if($0!~$3"/"$3) print }' | wc -l
  )"
fi

# DaemonSet readiness
DS_NOT_READY=0
if [[ -f "$DS_FILE" ]]; then
  DS_NOT_READY="$(
    grep -vE '^(NAME|NAMESPACE)' "$DS_FILE" |
    awk '{for(i=1;i<=NF;i++){
      if($i~/^[0-9]+\/[0-9]+$/){
        split($i,a,"/");
        if(a[1]!=a[2]) print;
      }
    }}' | wc -l
  )"
fi

# StatefulSet readiness
STS_NOT_READY=0
if [[ -f "$STS_FILE" ]]; then
  STS_NOT_READY="$(
    grep -vE '^(NAME|NAMESPACE)' "$STS_FILE" |
    awk '{for(i=1;i<=NF;i++){
      if($i~/^[0-9]+\/[0-9]+$/){
        split($i,a,"/");
        if(a[1]!=a[2]) print;
      }
    }}' | wc -l
  )"
fi

########################################
# PRINT SUMMARY
########################################

log "Total Pods"          "$TOTAL_PODS"
log "Running Pods"        "$RUNNING_PODS"
log "Pending Pods"        "$PENDING_PODS"
log "Failed Pods"         "$FAILED_PODS"

# Highlight issues
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

echo ""

log "Deployments"           "$TOTAL_DEPLOYS total"
log "Deployments NotReady"  "$DEPLOY_NOT_READY"

log "DaemonSets"            "$TOTAL_DAEMONSETS total"
log "DS NotReady"           "$DS_NOT_READY"

log "StatefulSets"          "$TOTAL_STS total"
log "STS NotReady"          "$STS_NOT_READY"

echo ""
