stage_trim() {
    local trim_dir="${OUTDIR}/trim"
    mkdir -p "$trim_dir"

    load_header "$SAMPLESHEET"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id library_type r1_fastq r2_fastq
        sample_id=$(get_field "$line" sample_id)
        [[ -n "${SAMPLE_FILTER:-}" && "$sample_id" != "$SAMPLE_FILTER" ]] && continue
        library_type=$(get_field "$line" library_type)
        r1_fastq=$(get_field "$line" r1_fastq)
        r2_fastq=$(get_field "$line" r2_fastq)

        local out_r1="${trim_dir}/${sample_id}_R1.trimmed.fastq.gz"
        local out_r2="${trim_dir}/${sample_id}_R2.trimmed.fastq.gz"
        local report_html="${trim_dir}/${sample_id}.fastp.html"
        local report_json="${trim_dir}/${sample_id}.fastp.json"

        if [[ "$library_type" == "paired" ]]; then
            fastp \
                -i "$r1_fastq" -I "$r2_fastq" \
                -o "$out_r1" -O "$out_r2" \
                -h "$report_html" -j "$report_json" \
                --thread "${THREADS}" \
                2>> "${trim_dir}/${sample_id}.fastp.log"
        else
            fastp \
                -i "$r1_fastq" \
                -o "$out_r1" \
                -h "$report_html" -j "$report_json" \
                --thread "${THREADS}" \
                2>> "${trim_dir}/${sample_id}.fastp.log"
        fi

        if [[ ! -s "$out_r1" ]]; then
            echo "ERROR: ${sample_id}: fastp produced no trimmed R1" >&2
            exit 67
        fi
        if [[ "$library_type" == "paired" && ! -s "$out_r2" ]]; then
            echo "ERROR: ${sample_id}: fastp produced no trimmed R2" >&2
            exit 67
        fi

        echo "stage_trim: ${sample_id} OK" >&2
    done < <(tail -n +2 "$SAMPLESHEET")
}
