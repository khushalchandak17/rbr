#!/usr/bin/env bash
# cluster.sh – Kubernetes Cluster Health Summary

hdr "K8s CLUSTER HEALTH SUMMARY"

# ----------------------------------------------------
# Detect & print Kubernetes distribution (k3s, rke2, kubeadm)
# ----------------------------------------------------
DISTRO_PRINT="**$K8S_DISTRO**"
[[ "$K8S_DISTRO" == "none" ]] && DISTRO_PRINT="N/A"
log "Distribution" "$DISTRO_PRINT"

# ----------------------------------------------------
# Server Version
# ----------------------------------------------------
SERVER_VERSION="N/A"
VERSION_FILE="$KUBECTL_DIR/version"

if [[ -f "$VERSION_FILE" ]]; then
    SERVER_VERSION="$(grep -o 'Server Version:.*' "$VERSION_FILE" 2>/dev/null \
        | sed 's/Server Version: //' | head -n1)"
    [[ -z "$SERVER_VERSION" ]] && SERVER_VERSION="N/A"
fi

log "Server Version" "**${SERVER_VERSION}**"

# ----------------------------------------------------
# Total Nodes
# ----------------------------------------------------
NODES_FILE="$KUBECTL_DIR/nodes"

NODE_TOTAL="$(count_rows_file "$NODES_FILE")"
NODE_READY="$(count_pattern_in_file '\bReady\b' "$NODES_FILE")"

# (Ready is counted from repeating “Ready” in the conditions column)
NODE_NOTREADY=$(( NODE_TOTAL - NODE_READY ))
(( NODE_NOTREADY < 0 )) && NODE_NOTREADY=0

log "Total Nodes" "**$NODE_TOTAL**"
log "Ready Nodes" "**$NODE_READY**"
log "NotReady Nodes" "**$NODE_NOTREADY**"

# ----------------------------------------------------
# Number of Namespaces
# ----------------------------------------------------
NS_FILE="$KUBECTL_DIR/namespaces"
NS_COUNT="$(count_rows_file "$NS_FILE")"
log "Total Namespaces" "$NS_COUNT"

# ----------------------------------------------------
# Warning / Failed events summary
# ----------------------------------------------------
EVENTS_FILE="$KUBECTL_DIR/events"
WARN_EVENTS="$(count_pattern_in_file 'Warning|Failed' "$EVENTS_FILE")"
log "Warning/Failed Events" "$WARN_EVENTS"

echo ""
