stage_validate() {
    local problems=0
    local sample_ids=()

    load_header "$SAMPLESHEET"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id library_type r1_fastq r2_fastq
        sample_id=$(get_field "$line" sample_id)
        [[ -n "${SAMPLE_FILTER:-}" && "$sample_id" != "$SAMPLE_FILTER" ]] && continue
        library_type=$(get_field "$line" library_type)
        r1_fastq=$(get_field "$line" r1_fastq)
        r2_fastq=$(get_field "$line" r2_fastq)

        sample_ids+=("$sample_id")

        if [[ ! -f "$r1_fastq" ]]; then
            echo "ERROR: ${sample_id}: r1_fastq not found: ${r1_fastq}" >&2
            problems=$(( problems + 1 ))
        elif ! gzip -t "$r1_fastq" 2>/dev/null; then
            echo "ERROR: ${sample_id}: r1_fastq is truncated or not valid gzip: ${r1_fastq}" >&2
            problems=$(( problems + 1 ))
        fi

        if [[ "$library_type" == "paired" ]]; then
            if [[ -z "$r2_fastq" ]]; then
                echo "ERROR: ${sample_id}: library_type is paired but r2_fastq is empty" >&2
                problems=$(( problems + 1 ))
            elif [[ ! -f "$r2_fastq" ]]; then
                echo "ERROR: ${sample_id}: r2_fastq not found: ${r2_fastq}" >&2
                problems=$(( problems + 1 ))
            elif ! gzip -t "$r2_fastq" 2>/dev/null; then
                echo "ERROR: ${sample_id}: r2_fastq is truncated or not valid gzip: ${r2_fastq}" >&2
                problems=$(( problems + 1 ))
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
    done < <(tail -n +2 "$SAMPLESHEET")

    local dups
    dups=$(printf '%s\n' "${sample_ids[@]}" | sort | uniq -d)
    if [[ -n "$dups" ]]; then
        while IFS= read -r d; do
            echo "ERROR: duplicate sample_id: ${d}" >&2
            problems=$(( problems + 1 ))
        done <<< "$dups"
    fi

    if (( problems > 0 )); then
        echo "stage_validate: ${problems} problem(s) found" >&2
        exit 65
    fi

    echo "stage_validate: all samples OK" >&2
}
