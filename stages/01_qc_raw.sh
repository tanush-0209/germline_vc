stage_qc_raw() {
    local qc_dir="${OUTDIR}/qc_raw"
    mkdir -p "$qc_dir"

    load_header "$SAMPLESHEET"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id library_type r1_fastq r2_fastq
        sample_id=$(get_field "$line" sample_id)
        [[ -n "${SAMPLE_FILTER:-}" && "$sample_id" != "$SAMPLE_FILTER" ]] && continue
        library_type=$(get_field "$line" library_type)
        r1_fastq=$(get_field "$line" r1_fastq)
        r2_fastq=$(get_field "$line" r2_fastq)

        if [[ "$library_type" == "paired" ]]; then
            fastqc -o "$qc_dir" "$r1_fastq" "$r2_fastq" 2>> "${qc_dir}/${sample_id}.fastqc.log"
        else
            fastqc -o "$qc_dir" "$r1_fastq" 2>> "${qc_dir}/${sample_id}.fastqc.log"
        fi

        local r1_base
        r1_base=$(basename "$r1_fastq")
        r1_base=${r1_base%.fastq.gz}
        if [[ ! -s "${qc_dir}/${r1_base}_fastqc.html" ]]; then
            echo "ERROR: ${sample_id}: FastQC produced no report for R1" >&2
            exit 66
        fi

        if [[ "$library_type" == "paired" ]]; then
            local r2_base
            r2_base=$(basename "$r2_fastq")
            r2_base=${r2_base%.fastq.gz}
            if [[ ! -s "${qc_dir}/${r2_base}_fastqc.html" ]]; then
                echo "ERROR: ${sample_id}: FastQC produced no report for R2" >&2
                exit 66
            fi
        fi

        echo "stage_qc_raw: ${sample_id} OK" >&2
    done < <(tail -n +2 "$SAMPLESHEET")
}
