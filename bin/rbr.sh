#!/usr/bin/env bash
#
# RBR v4.3 – Rancher Bundle Reader (Final Stable Version)
#
# FIXES in v4.3:
# 1. IMMEDIATE INPUT SANITIZATION: Fixes the "Unknown command: %" error by stripping \r
#    from arguments at the absolute entry point of the script.
# 2. FEATURE: Added 'rbr ls' command to list all available Kubernetes resources
#    from the extracted bundle's kubectl directory.

RBR_VERSION="4.3"
RBR_ROOT="." # Always use the current working directory in v4.x

# --- Configuration (Modify these paths if needed) ---
CLUSTER_SUMMARY_SCRIPT="${CLUSTER_SUMMARY_SCRIPT:-./data/cluster-summary.sh}"
GEMINI_CMD="${GEMINI_CMD:-gemini}"

# ---------------- logging ----------------
rbr_log()  { echo "🔹 $*"; }
rbr_warn() { echo "⚠️  $*" >&2; }
rbr_err()  { echo "❌ $*" >&2; }

# ---------------- strict wrapper ----------------
rbr_strict() {
  (
    # Set strict mode for reliable execution within functions
    set -euo pipefail
    "$@"
  )
}

# ---------------- utilities ----------------

rbr_sanitize() {
  # Use tr to remove any carriage return characters (\r) from the input string
  # This is the fix for "Unknown command: %" error.
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
      rbr_err "HINT: Check if the bundle is fully extracted and contains the 'kubectl' folder."
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

  # Argument Parsing for -n
  while [[ $# -gt 0 ]]; do
    case "$(rbr_sanitize "$1")" in
      -n|--namespace)
        [[ $# -lt 2 ]] && { rbr_err "Missing value for $1"; return 1; }
        ns="$(rbr_sanitize "$2")" # Sanitize the namespace value
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
    sts|statefulsets) file="statefulsets" ;; # Added based on your ls output
    ds|daemonsets) file="daemonsets" ;;       # Added based on your ls output
    svc|services) file="services" ;;          # Added based on your ls output
    pv) file="pv" ;;                          # Added based on your ls output
    pvc) file="pvc" ;;                        # Added based on your ls output
    roles) file="roles" ;;                    # Added based on your ls output
    *) rbr_err "Unsupported resource: $resource"; return 1 ;;
  esac

  local path="$RBR_ROOT/$distro/kubectl/$file"
  [[ -f "$path" ]] || { rbr_err "Missing file: $path"; rbr_err "Expected path: $path"; return 1; }

  rbr_log "Reading $resource (${ns:-all}) from $distro"

  # Data Extraction
  if [[ -n "$ns" ]]; then
    # Grep for the namespace at the beginning of the line
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

    # List files and process them to show shortcuts
    command ls "$kubectl_dir" | command grep -vE "$ignored_files" | while read -r resource; do
        # Use a case statement to show the kubectl-style short name
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
    local prompt_text="Please perform a full diagnostic analysis on the cluster bundle. The bundle root directory is the current working directory: '$PWD'. You MUST use the available MCP tools (cluster_bundle_debugger) to gather and analyze the necessary data and provide a detailed RCA."

    "$GEMINI_CMD" -p "$prompt_text"

  else
    rbr_log "Generating Basic Text Summary (using cluster-summary.sh)"
    # Use 'eval' for safe expansion of the user home directory in the script path
    eval "DEBUG=1 command bash \"${CLUSTER_SUMMARY_SCRIPT}\" \"$RBR_ROOT\""
  fi
}
rbr_cs() { rbr_strict _rbr_cs "$@"; }


# ---------------- IMMEDIATE INPUT SANITIZATION (CRITICAL FIX) ----------------
# This loop sanitizes all input arguments ($@) immediately upon script execution.
# This prevents the Zsh/Carriage Return issue from breaking the dispatcher logic.
declare -a clean_args=()
for arg in "$@"; do
    clean_args+=("$(rbr_sanitize "$arg")")
done
set -- "${clean_args[@]}"
# ---------------- END SANITIZATION ----------------


# ---------------- dispatcher ----------------
rbr_main() {
  local cmd="${1:-}"
  if [[ $# -gt 0 ]]; then shift; fi

  case "$cmd" in
    get) rbr_get "$@" ;;
    ls) rbr_ls "$@" ;; # NEW
    cs|clustersummary) rbr_cs "$@" ;;
    status) rbr_status ;;
    reset) rbr_reset ;;
    ""|help)
      cat <<EOF
RBR v$RBR_VERSION – Rancher Bundle Reader

Directory-Local Mode: The tool always acts on the current directory.
Run 'cd /path/to/extracted/bundle' before executing.

Usage:
  rbr ls                     - List all available resource types (e.g., pods, cm).
  rbr get <resource> [-n <ns>] - Display resource content (e.g., rbr get po -n kube-system).
  rbr cs [ai|text]           - Run the cluster summary and diagnosis.
EOF
      ;;
    *) rbr_err "Unknown command: $cmd" ;;
  esac
}

rbr_main "$@"
