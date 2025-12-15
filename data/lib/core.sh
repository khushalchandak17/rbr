#!/usr/bin/env bash
# core.sh – shared formatting, output helpers, numeric utilities

# -----------------------------------------------------
# 🌟 Output Formatting Helpers
# -----------------------------------------------------

hdr() {
    echo ""
    echo "==============================================="
    echo " 📌 $1"
    echo "==============================================="
}

subhdr() {
    echo ""
    echo "  --- $1 ---"
}

log() {
    # $1 = key, $2 = value
    printf "  %-28s %s\n" "$1:" "$2"
}

# success / warning / error
ok()    { echo "  [✔] $1"; }
warn()  { echo "  [⚠] $1"; }
err()   { echo "  [✘] $1"; }

# -----------------------------------------------------
# 🔢 Numeric utilities
# -----------------------------------------------------

# Strip non-numeric characters; fallback 0
num() {
    local v="${1:-0}"
    printf '%s' "$v" | tr -cd '0-9'
}

# Ensure integer result or 0
int_or_zero() {
    local out
    out="$(num "$1")"
    [[ -z "$out" ]] && out=0
    echo "$out"
}
