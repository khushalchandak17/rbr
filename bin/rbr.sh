#!/usr/bin/env bash
#
# RBR v4.4 – Rancher Bundle Reader (Final Stable Version)
#
# CHANGES in v4.4:
# 1. Self-contained: Dynamically finds cluster-summary.sh in ../data/
# 2. AI Fix: Updated prompt to force use of 'auto_diagnose' tool.
# 3. Sanitization: Fixes Windows carriage return bugs.

RBR_VERSION="4.4"
RBR_ROOT="." 

# --- Dynamic Path Resolution ---
# Resolve the directory where this script (or its symlink) resides
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do 
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" 
done
# Get the installation root (one level up from bin/)
INSTALL_DIR="$( cd -P "$( dirname "$SOURCE" )/.." >/dev/null 2>&1 && pwd )"

# Set path to the bundled cluster-summary script
if [[ -f "$INSTALL_DIR/data/cluster-summary.sh" ]]; then
    CLUSTER_SUMMARY_SCRIPT="$INSTALL_DIR/data/cluster-summary.sh"
else
    # Fallback default if not found (e.g. running raw script without data folder)
    CLUSTER_SUMMARY_SCRIPT="${CLUSTER_SUMMARY_SCRIPT:-/var/rbr/data/cluster-summary.sh}"
fi

GEMINI_CMD="${GEMINI_CMD:-gemini}"

# ---------------- logging ----------------
rbr_log()  { echo "🔹 $*"; }
rbr_warn() { echo "⚠️  $*" >&2; }
rbr_err()  { echo "❌ $*" >&2; }

# ---------------- strict wrapper ----------------
rbr_strict() {
  (
    set -euo pipefail
    "$@"
  )
}

# ---------------- utilities ----------------
rbr_sanitize() {
  echo "$1" | command tr -d '\r'
}

# ---------------- bundle validation ----------------
rbr_detect_distro() {
  local root_path="$1"
  if [[ -d "$root_path/k3s" ]]; then
    echo k3s
  elif [[ -d "$root_path/rke2" ]]; then
    echo rke2
  else
    echo unknown
  fi
}

rbr_validate_context() {
  local distro root_path="$1"
  distro="$(rbr_detect_distro "$root_path")"

  if [[ "$distro" == "unknown" ]]; then
      rbr_err "Cannot detect k3s or rke2 directory structure in the current directory."
      rbr_err "HINT: Please run 'cd /path/to/extracted/bundle' first."
      return 1
  fi
  
  if [[ ! -d "$root_path/$distro/kubectl" ]]; then
      rbr_err "Found '$distro', but the expected '$distro/kubectl' directory is missing."
      return 1
  fi
  
  echo "$distro"
}

# ---------------- rbr get ----------------
_rbr_get() {
  local resource; resource="$1"; shift || true
  local ns=""

  local distro
  distro="$(rbr_validate_context "$RBR_ROOT")" || return 1

  while [[ $# -gt 0 ]]; do
    case "$(rbr_sanitize "$1")" in
      -n|--namespace)
        [[ $# -lt 2 ]] && { rbr_err "Missing value for $1"; return 1; }
        ns="$(rbr_sanitize "$2")"
        shift 2
        ;;
      *) rbr_err "Unknown arg: $1. Use -n <namespace>"; return 1 ;;
    esac
  done

  # Resource Mapping
  local file=""
  case "$resource" in
    nodes|no) file="nodes" ;;
    pods|po) file="pods" ;;
    ns|namespaces) file="namespaces" ;;
    cm|configmaps) file="configmaps" ;;
    deploy|deployments) file="deployments" ;;
    sts|statefulsets) file="statefulsets" ;;
    ds|daemonsets) file="daemonsets" ;;
    svc|services) file="services" ;;
    pv) file="pv" ;;
    pvc) file="pvc" ;;
    roles) file="roles" ;;
    *) rbr_err "Unsupported resource: $resource"; return 1 ;;
  esac

  local path="$RBR_ROOT/$distro/kubectl/$file"
  [[ -f "$path" ]] || { rbr_err "Missing file: $path"; return 1; }

  rbr_log "Reading $resource (${ns:-all}) from $distro"

  if [[ -n "$ns" ]]; then
    command grep -E "^${ns}[[:space:]]" "$path" || true
  else
    command cat "$path"
  fi
}
rbr_get() { rbr_strict _rbr_get "$@"; }

# ---------------- rbr ls ----------------
rbr_list_resources() {
    local distro
    distro="$(rbr_validate_context "$RBR_ROOT")" || return 1
    local kubectl_dir="$RBR_ROOT/$distro/kubectl"
    local ignored_files='(api-resources|apiservices|nodesdescribe|version|rancher-prov)'

    rbr_log "Available kubectl resources in $distro/kubectl:"
    command ls "$kubectl_dir" | command grep -vE "$ignored_files" | while read -r resource; do
        case "$resource" in
            pods) echo -e "  pods (po)" ;;
            namespaces) echo -e "  namespaces (ns)" ;;
            configmaps) echo -e "  configmaps (cm)" ;;
            deployments) echo -e "  deployments (deploy)" ;;
            services) echo -e "  services (svc)" ;;
            statefulsets) echo -e "  statefulsets (sts)" ;;
            daemonsets) echo -e "  daemonsets (ds)" ;;
            clusterroles) echo -e "  clusterroles (cr)" ;;
            clusterrolebindings) echo -e "  clusterrolebindings (crb)" ;;
            nodes) echo -e "  nodes (no)" ;;
            *) echo -e "  $resource" ;;
        esac
    done
}
rbr_ls() { rbr_strict rbr_list_resources "$@"; }

# ---------------- rbr cs ----------------
_rbr_cs() {
  local root mode; root="$RBR_ROOT"; mode="$(rbr_sanitize "${1:-text}")"
  local distro
  distro="$(rbr_validate_context "$root")" || return 1

  if [[ "$mode" == "ai" ]]; then
    rbr_log "Invoking Gemini AI Diagnosis on $distro bundle via MCP Server..."
    
    # CRITICAL FIX: Explicitly instruct AI to use the specific tool function name
    local prompt_text="Perform a full cluster diagnosis immediately. You have a tool named 'auto_diagnose' already loaded. Call 'auto_diagnose' with arguments: {'bundle': '$PWD', 'distro': '$distro'}. Do NOT try to connect to a server. Do NOT check for tool existence. Just call the tool."

    "$GEMINI_CMD" -p "$prompt_text"
  else
    rbr_log "Generating Basic Text Summary (using cluster-summary.sh)"
    eval "DEBUG=1 command bash \"${CLUSTER_SUMMARY_SCRIPT}\" \"$RBR_ROOT\""
  fi
}
rbr_cs() { rbr_strict _rbr_cs "$@"; }

# ---------------- IMMEDIATE INPUT SANITIZATION ----------------
declare -a clean_args=()
for arg in "$@"; do
    clean_args+=("$(rbr_sanitize "$arg")")
done
set -- "${clean_args[@]}"

# ---------------- dispatcher ----------------
rbr_main() {
  local cmd="${1:-}"
  if [[ $# -gt 0 ]]; then shift; fi

  case "$cmd" in
    get) rbr_get "$@" ;;
    ls) rbr_ls "$@" ;; 
    cs|clustersummary) rbr_cs "$@" ;;
    status) rbr_status ;;
    reset) rbr_reset ;;
    ""|help)
      cat <<EOF
RBR v$RBR_VERSION – Rancher Bundle Reader

Directory-Local Mode: The tool always acts on the current directory.
Run 'cd /path/to/extracted/bundle' before executing.

Usage:
  rbr ls                       - List all available resource types.
  rbr get <resource> [-n <ns>] - Display resource content.
  rbr cs [ai|text]             - Run the cluster summary and diagnosis.
EOF
      ;;
    *) rbr_err "Unknown command: $cmd" ;;
  esac
}

rbr_main "$@"
