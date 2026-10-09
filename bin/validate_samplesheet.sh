#!/usr/bin/env bash
set -euo pipefail

SHEET=${1:?usage: validate_samplesheet.sh <samplesheet>}

IFS=',' read -r -a HEADER < "$SHEET"
field_index() {
    local name="$1" i
    for i in "${!HEADER[@]}"; do
        [[ "${HEADER[$i]}" == "$name" ]] && { echo "$i"; return 0; }
    done
    return 1
}

idx_sample_id=$(field_index sample_id)
idx_library_type=$(field_index library_type)
idx_r1=$(field_index r1_fastq)
idx_r2=$(field_index r2_fastq)

problems=0
sample_ids=()

while IFS=',' read -r -a fields; do
    sample_id="${fields[$idx_sample_id]}"
    library_type="${fields[$idx_library_type]}"
    r1_fastq="${fields[$idx_r1]}"
    r2_fastq="${fields[$idx_r2]:-}"
    sample_ids+=("$sample_id")

    r1_base=$(basename "$r1_fastq")
    if [[ ! -f "$r1_base" ]]; then
        echo "ERROR: ${sample_id}: r1_fastq not found: ${r1_base}" >&2
        problems=$(( problems + 1 ))
    elif ! gzip -t "$r1_base" 2>/dev/null; then
        echo "ERROR: ${sample_id}: r1_fastq is truncated or not valid gzip: ${r1_base}" >&2
        problems=$(( problems + 1 ))
    fi

    if [[ "$library_type" == "paired" ]]; then
        if [[ -z "$r2_fastq" ]]; then
            echo "ERROR: ${sample_id}: library_type is paired but r2_fastq is empty" >&2
            problems=$(( problems + 1 ))
        else
            r2_base=$(basename "$r2_fastq")
            if [[ ! -f "$r2_base" ]]; then
                echo "ERROR: ${sample_id}: r2_fastq not found: ${r2_base}" >&2
                problems=$(( problems + 1 ))
            elif ! gzip -t "$r2_base" 2>/dev/null; then
                echo "ERROR: ${sample_id}: r2_fastq is truncated or not valid gzip: ${r2_base}" >&2
                problems=$(( problems + 1 ))
            fi
        fi
    elif [[ "$library_type" == "single" ]]; then
        if [[ -n "$r2_fastq" ]]; then
            echo "ERROR: ${sample_id}: library_type is single but r2_fastq is not empty: ${r2_fastq}" >&2
            problems=$(( problems + 1 ))
        fi
    else
        echo "ERROR: ${sample_id}: unrecognized library_type: ${library_type}" >&2
        problems=$(( problems + 1 ))
    fi
done < <(tail -n +2 "$SHEET")

dups=$(printf '%s\n' "${sample_ids[@]}" | sort | uniq -d)
if [[ -n "$dups" ]]; then
    while IFS= read -r d; do
        echo "ERROR: duplicate sample_id: ${d}" >&2
        problems=$(( problems + 1 ))
    done <<< "$dups"
fi

if (( problems > 0 )); then
    echo "validate_samplesheet: ${problems} problem(s) found" >&2
    exit 65
fi

echo "validate_samplesheet: all samples OK" >&2
