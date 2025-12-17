#!/usr/bin/env bash
# detect.sh – detect bundle type, K8s distro, OS vendor

# Exports:
#   BUNDLE_TYPE
#   K8S_DISTRO
#   OS_VENDOR

# -----------------------------------------------------
# 🔍 Detect Kubernetes Distribution (k3s, rke2, kubeadm)
# -----------------------------------------------------

detect_k8s_distro() {
    local root="$1"

    if [[ -d "$root/k3s" ]]; then
        K8S_DISTRO="k3s"
    elif [[ -d "$root/rke2" ]]; then
        K8S_DISTRO="rke2"
    elif [[ -d "$root/kubeadm" ]]; then
        K3S_DISTRO="kubeadm"
    else
        K8S_DISTRO="none"
    fi

    export K8S_DISTRO
}

# -----------------------------------------------------
# 🧩 Detect Bundle Type (Rancher, K8s, Harvester, Longhorn, OS)
# -----------------------------------------------------

detect_bundle_type() {
    local root="$1"

    if [[ -d "$root/rancher" ]]; then
        BUNDLE_TYPE="rancher"
    elif [[ -d "$root/harvester" ]]; then
        BUNDLE_TYPE="harvester"
    elif ls "$root"/longhorn-* &>/dev/null; then
        BUNDLE_TYPE="longhorn"
    elif [[ "$K8S_DISTRO" != "none" ]]; then
        BUNDLE_TYPE="k8s"
    else
        BUNDLE_TYPE="os"
    fi

    export BUNDLE_TYPE
}

# -----------------------------------------------------
# 🖥 Detect OS Vendor (Ubuntu / SUSE / RHEL / Rocky / Alma / Amazon)
# -----------------------------------------------------

detect_os() {
    local root="$1"
    local osfile="$root/systeminfo/osrelease"

    OS_VENDOR="unknown"

    if [[ -f "$osfile" ]]; then
        local id
        id="$(grep -i '^ID=' "$osfile" | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
        [[ -n "$id" ]] && OS_VENDOR="$id"
    fi

    export OS_VENDOR
}
