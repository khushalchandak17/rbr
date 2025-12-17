#!/usr/bin/env bash
#
# cluster-summary.sh
# Modular Kubernetes / Rancher / Harvester / Longhorn diagnostics framework
#
# Usage:
#   ./cluster-summary.sh [bundle_path] [--system|--cluster|--network|--workloads|--controlplane|--events|--troubleshoot] [--debug]
#

set -euo pipefail

# -----------------------------------------------------
# 📌 Determine base directory and bundle root
# -----------------------------------------------------
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-.}"

# Shift ROOT if it was the first argument and not a flag
if [[ "$ROOT" == --* ]]; then
    ROOT="."
else
    shift || true
fi

# -----------------------------------------------------
# 📌 Parse global flags (debug, module selection)
# -----------------------------------------------------
ACTION="all"
DEBUG_MODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG_MODE=1
            ;;
        --system)
            ACTION="system"
            ;;
        --cluster)
            ACTION="cluster"
            ;;
        --network|--net)
            ACTION="network"
            ;;
        --workloads|--pods)
            ACTION="workloads"
            ;;
        --controlplane|--cp)
            ACTION="controlplane"
            ;;
        --events)
            ACTION="events"
            ;;
        --troubleshoot|--ts)
            ACTION="troubleshoot"
            ;;
        --help|-h)
            echo "Usage: cluster-summary.sh [bundle_path] [options]"
            echo ""
            echo "Options:"
            echo "  --system         Show only system info"
            echo "  --cluster        Show only cluster health"
            echo "  --network        Show only CNI + networking info"
            echo "  --workloads      Show only pod status, DS/SS/Deployments"
            echo "  --controlplane   Show API/etcd config"
            echo "  --events         Show warnings/errors"
            echo "  --troubleshoot   Deep troubleshooting mode"
            echo "  --debug          Enable debug tracing"
            echo ""
            exit 0
            ;;
    esac
    shift
done

# -----------------------------------------------------
# 📌 Enable DEBUG MODE (bash -x)
# -----------------------------------------------------
if [[ "$DEBUG_MODE" == 1 ]]; then
    echo "[DEBUG] Debug mode enabled"
    set -x
fi

# -----------------------------------------------------
# 📌 Load core + detection modules
# -----------------------------------------------------
source "$BASE_DIR/lib/core.sh"
source "$BASE_DIR/lib/detect.sh"
source "$BASE_DIR/lib/utils.sh"

# -----------------------------------------------------
# 📌 Perform detection
# -----------------------------------------------------
detect_k8s_distro "$ROOT"
detect_bundle_type "$ROOT"
detect_os "$ROOT"

# -----------------------------------------------------
# 📌 Export environment variables for all modules
# -----------------------------------------------------
export ROOT
export BASE_DIR
export BUNDLE_TYPE
export K8S_DISTRO
export OS_VENDOR

# Define directories (may be empty if not applicable)
export KUBECTL_DIR="$ROOT/$K8S_DISTRO/kubectl"
export CRICTL_DIR="$ROOT/$K8S_DISTRO/crictl"
export SYSTEMINFO_DIR="$ROOT/systeminfo"
export NETWORK_DIR="$ROOT/networking"

# -----------------------------------------------------
# 📌 Banner
# -----------------------------------------------------
echo ""
echo "==============================================="
echo " 🚀 Cluster Summary (Modular Diagnostic Engine)"
echo "==============================================="
echo " Bundle Path : $ROOT"
echo " Bundle Type : $BUNDLE_TYPE"
echo " K8s Distro  : ${K8S_DISTRO:-none}"
echo " OS Vendor   : ${OS_VENDOR:-unknown}"
echo " Debug Mode  : $([[ $DEBUG_MODE == 1 ]] && echo Enabled || echo Disabled)"
echo "-----------------------------------------------"
echo ""

# -----------------------------------------------------
# 📌 Dispatch modules based on ACTION
# -----------------------------------------------------
case "$ACTION" in
    all)
        source "$BASE_DIR/lib/system.sh"
        source "$BASE_DIR/lib/cluster.sh"
        source "$BASE_DIR/lib/networking.sh"
        source "$BASE_DIR/lib/workloads.sh"
        source "$BASE_DIR/lib/controlplane.sh"
        source "$BASE_DIR/lib/events.sh"
        ;;
    system)
        source "$BASE_DIR/lib/system.sh"
        ;;
    cluster)
        source "$BASE_DIR/lib/cluster.sh"
        ;;
    network)
        source "$BASE_DIR/lib/networking.sh"
        ;;
    workloads)
        source "$BASE_DIR/lib/workloads.sh"
        ;;
    controlplane)
        source "$BASE_DIR/lib/controlplane.sh"
        ;;
    events)
        source "$BASE_DIR/lib/events.sh"
        ;;
    troubleshoot)
        source "$BASE_DIR/lib/troubleshoot.sh"
        ;;
esac

echo ""
echo "==============================================="
echo " 🏁 Summary Complete"
echo "==============================================="
echo ""
