#!/usr/bin/env bash
set -euo pipefail

# ---- config: only these three names appear anywhere in the stages ----
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}

# ---- logging ----
log() { echo "$*" >&2; }
die() {
    local msg="$1" code="${2:-1}"
    echo "ERROR: ${msg}" >&2
    exit "$code"
}

# ---- samplesheet: read by column name, not position ----
declare -a SHEET_HEADER

load_header() {
    local sheet="$1"
    IFS=',' read -r -a SHEET_HEADER < <(head -n1 "$sheet")
}

field_index() {
    local name="$1" i
    for i in "${!SHEET_HEADER[@]}"; do
        [[ "${SHEET_HEADER[$i]}" == "$name" ]] && { echo "$i"; return 0; }
    done
    return 1
}

get_field() {
    local line="$1" name="$2" idx
    idx=$(field_index "$name") || die "no such column: ${name}"
    local -a fields
    IFS=',' read -r -a fields <<< "$line"
    echo "${fields[$idx]:-}"
}

# One data row by 1-based index (1 = first row after the header).
# Prints the matching line; returns non-zero and prints nothing if the row doesn't exist.
get_row() {
    local sheet="$1" n="$2"
    awk -F',' -v n="$n" 'NR == n + 1 { print; found=1 } END { exit !found }' "$sheet"
}
