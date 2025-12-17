#!/usr/bin/env bash

# ============================================================
#  K8s Events Summary Module
#  This module:
#   • Detects events file in kubectl directory
#   • Handles "No resources found" cleanly
#   • Summarizes Warning/Error events
#   • Summaries by Namespace, Reason, Source
# ============================================================

events_summary() {
  hdr "K8s EVENTS SUMMARY"

  # ------------------------------------------------------------
  # Auto-detect events file inside bundle
  # ------------------------------------------------------------
  if [[ -f "$KUBECTL_DIR/events" ]]; then
    EVENTS_FILE="$KUBECTL_DIR/events"
  elif [[ -f "$KUBECTL_DIR/events.txt" ]]; then
    EVENTS_FILE="$KUBECTL_DIR/events.txt"
  elif [[ -f "$KUBECTL_DIR/get-events" ]]; then
    EVENTS_FILE="$KUBECTL_DIR/get-events"
  else
    log "Events" "N/A (events file missing)"
    echo ""
    return 0 2>/dev/null || true
  fi

  # ------------------------------------------------------------
  # Handle empty or "No resources found"
  # ------------------------------------------------------------
  if grep -qi "No resources found" "$EVENTS_FILE"; then
    log "Events" "No Kubernetes events recorded in this bundle"
    echo ""
    return 0 2>/dev/null || true
  fi

  if [[ ! -s "$EVENTS_FILE" ]]; then
    log "Events" "Empty events file"
    echo ""
    return 0 2>/dev/null || true
  fi

  # ------------------------------------------------------------
  # Remove header row and split into simplified TSV-like format
  # ------------------------------------------------------------
  CLEANED_EVENTS=$(awk '
    NR>1 {
      ns=$1; last=$2; type=$3; reason=$4; object=$5; source=$7;
      sub(/^[[:space:]]+/, "", ns);
      sub(/^[[:space:]]+/, "", type);
      print ns "\t" type "\t" reason "\t" source;
    }
  ' "$EVENTS_FILE")

  # If parsing failed
  if [[ -z "$CLEANED_EVENTS" ]]; then
    log "Events" "Unable to parse events table"
    echo ""
    return 0 2>/dev/null || true
  fi

  # ------------------------------------------------------------
  # Top Warning / Error Events
  # ------------------------------------------------------------
  echo "🔸 Top Warning/Error Events:"
  echo "$CLEANED_EVENTS" |
    awk -F'\t' '
      $2 == "Warning" || $2 == "Error" { print }
    ' |
    awk -F'\t' '
      { key=$1 " | " $2 " | " $3; count[key]++ }
      END {
        for (k in count) print count[k], k
      }
    ' |
    sort -rn | head -10 |
    awk '{print "  • " $0}'

  echo ""

  # ------------------------------------------------------------
  # Events by Namespace
  # ------------------------------------------------------------
  echo "🔸 Events by Namespace:"
  echo "$CLEANED_EVENTS" |
    awk -F'\t' '{ ns[$1]++ } END { for (n in ns) print ns[n], n }' |
    sort -rn | head -10 |
    awk '{print "  • " $0}'

  echo ""

  # ------------------------------------------------------------
  # Events by Reason
  # ------------------------------------------------------------
  echo "🔸 Top Event Reasons:"
  echo "$CLEANED_EVENTS" |
    awk -F'\t' '{ reason[$3]++ } END { for (r in reason) print reason[r], r }' |
    sort -rn | head -10 |
    awk '{print "  • " $0}'

  echo ""

  # ------------------------------------------------------------
  # Events by Source
  # ------------------------------------------------------------
  echo "🔸 Top Event Sources:"
  echo "$CLEANED_EVENTS" |
    awk -F'\t' '{ src[$4]++ } END { for (s in src) print src[s], s }' |
    sort -rn | head -10 |
    awk '{print "  • " $0}'

  echo ""
}

# Register function name
EVENTS_MODULE="events_summary"
