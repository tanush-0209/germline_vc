stage_postprocess() {
    local align_dir="${OUTDIR}/align"
    local post_dir="${OUTDIR}/postprocess"
    mkdir -p "$post_dir"

    load_header "$SAMPLESHEET"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id
        sample_id=$(get_field "$line" sample_id)
        [[ -n "${SAMPLE_FILTER:-}" && "$sample_id" != "$SAMPLE_FILTER" ]] && continue

        local in_bam="${align_dir}/${sample_id}.sorted.bam"
        local dedup_bam="${post_dir}/${sample_id}.dedup.bam"
        local metrics="${post_dir}/${sample_id}.dup_metrics.txt"
        local flagstat="${post_dir}/${sample_id}.flagstat.txt"

        gatk MarkDuplicates \
            -I "$in_bam" \
            -O "$dedup_bam" \
            -M "$metrics" \
            2>> "${post_dir}/${sample_id}.markdup.log"

        samtools index "$dedup_bam"
        samtools flagstat "$dedup_bam" > "$flagstat"

        if [[ ! -s "$dedup_bam" ]]; then
            echo "ERROR: ${sample_id}: MarkDuplicates produced no BAM" >&2
            exit 69
        fi
        if [[ ! -s "${dedup_bam}.bai" ]]; then
            echo "ERROR: ${sample_id}: dedup BAM index missing" >&2
            exit 69
        fi
        if [[ ! -s "$flagstat" ]]; then
            echo "ERROR: ${sample_id}: flagstat report missing" >&2
            exit 69
        fi

        echo "stage_postprocess: ${sample_id} OK" >&2
    done < <(tail -n +2 "$SAMPLESHEET")
}
