#!/usr/bin/env bash
# utils.sh – shared helper functions for file parsing, grep safety, counts

# -----------------------------------------------------
# Safe Grep (never fails script)
# -----------------------------------------------------
safe_grep() {
    grep "$@" 2>/dev/null || true
}

# -----------------------------------------------------
# First line of file or N/A
# -----------------------------------------------------
first_line_or_na() {
    local file="$1"
    [[ -f "$file" ]] && head -n1 "$file" || echo "N/A"
}

# -----------------------------------------------------
# Count matches of a regex in a file (returns 0 on missing file)
# -----------------------------------------------------
count_pattern_in_file() {
    local pattern="$1"
    local file="$2"

    [[ -f "$file" ]] || { echo 0; return; }

    local out
    out="$(grep -cE "$pattern" "$file" 2>/dev/null || echo 0)"
    int_or_zero "$out"
}

# -----------------------------------------------------
# Count non-header rows in a kubectl table
# -----------------------------------------------------
count_rows_file() {
    local file="$1"

    [[ -f "$file" ]] || { echo 0; return; }

    local count
    count="$(grep -vE '^(NAME|NAMESPACE)' "$file" 2>/dev/null | wc -l | awk '{print $1}')"

    int_or_zero "$count"
}

# -----------------------------------------------------
# Trim whitespace
# -----------------------------------------------------
trim() {
    local s="$1"
    printf '%s' "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
