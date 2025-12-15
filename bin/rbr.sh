#!/usr/bin/env bash
#
# RBR v4.0 – Rancher Bundle Reader (Stateless/Directory-Local Mode)
#
# USAGE: cd /path/to/extracted/bundle
#        ./rbr.sh get pods -n kube-system
#        ./rbr.sh cs ai

# Ensure the script is executable (chmod +x rbr.sh)

RBR_VERSION="4.0"

# --- Configuration (Modify these paths) ---
CLUSTER_SUMMARY_SCRIPT="${CLUSTER_SUMMARY_SCRIPT:-$HOME/work/HACKWEEK-PRO/code/cluster-summary/cluster-summary.sh}"
GEMINI_CMD="${GEMINI_CMD:-gemini}"

# The current directory is always the bundle root in this mode
RBR_ROOT="."

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
  local resource="$1"; shift || true
  local ns=""

  local distro
  distro="$(rbr_validate_context "$RBR_ROOT")" || return 1

  # Argument Parsing for -n
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        [[ $# -lt 2 ]] && { rbr_err "Missing value for $1"; return 1; }
        ns="$2"
        shift 2
        ;;
      *) rbr_err "Unknown arg: $1. Use -n <namespace>"; return 1 ;;
    esac
  done

  # Resource Mapping
  local file=""
  case "$resource" in
    pods|po) file="pods" ;;
    ns|namespaces) file="namespaces" ;;
    cm|configmaps) file="configmaps" ;;
    deploy|deployments) file="deployments" ;;
    *) rbr_err "Unsupported resource: $resource"; return 1 ;;
  esac

  local path="$RBR_ROOT/$distro/kubectl/$file"
  [[ -f "$path" ]] || { rbr_err "Missing file: $path"; return 1; }

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

# ---------------- rbr cs ----------------
_rbr_cs() {
  local mode="${1:-text}"
  local distro
  distro="$(rbr_validate_context "$RBR_ROOT")" || return 1

  if [[ "$mode" == "ai" ]]; then
    rbr_log "Invoking Gemini AI Diagnosis on $distro bundle via MCP Server..."
    local prompt_text="Please perform a full diagnostic analysis on the cluster bundle. The bundle root directory is the current working directory: '$PWD'. You MUST use the available MCP tools (cluster_bundle_debugger) to gather and analyze the necessary data and provide a detailed RCA."

    # Execute the Gemini CLI. It will read the current PWD via the prompt.
    "$GEMINI_CMD" -p "$prompt_text"

  else
    rbr_log "Generating Basic Text Summary (using cluster-summary.sh)"
    # Use 'eval' for safe expansion of the user home directory in the script path
    eval "DEBUG=1 command bash \"${CLUSTER_SUMMARY_SCRIPT}\" \"$RBR_ROOT\""
  fi
}
rbr_cs() { rbr_strict _rbr_cs "$@"; }


# ---------------- dispatcher ----------------
rbr_main() {
  local cmd="${1:-}"
  if [[ $# -gt 0 ]]; then shift; fi

  case "$cmd" in
    get) rbr_get "$@" ;;
    cs|clustersummary) rbr_cs "$@" ;;
    ""|help)
      cat <<EOF
RBR v$RBR_VERSION – Rancher Bundle Reader

Directory-Local Mode: The tool always acts on the current directory.
Run 'cd /path/to/extracted/bundle' before executing.

Usage:
  ./rbr.sh get pods [-n <ns>]
  ./rbr.sh cs [ai|text]
  ./rbr.sh help
EOF
      ;;
    *) rbr_err "Unknown command: $cmd" ;;
  esac
}

rbr_main "$@"%
