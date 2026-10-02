stage_align() {
    local align_dir="${OUTDIR}/align"
    mkdir -p "$align_dir"

    load_header "$SAMPLESHEET"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id library_type
        sample_id=$(get_field "$line" sample_id)
        [[ -n "${SAMPLE_FILTER:-}" && "$sample_id" != "$SAMPLE_FILTER" ]] && continue
        library_type=$(get_field "$line" library_type)

        local trim_r1="${OUTDIR}/trim/${sample_id}_R1.trimmed.fastq.gz"
        local trim_r2="${OUTDIR}/trim/${sample_id}_R2.trimmed.fastq.gz"
        local bam="${align_dir}/${sample_id}.sorted.bam"
        local align_log="${align_dir}/${sample_id}.bwa.log"
        local sort_tmp="${TMPDIR:-/tmp}/${sample_id}.sort"

        if [[ "$library_type" == "paired" ]]; then
            bwa mem -t "${THREADS}" \
                -R "@RG\tID:${sample_id}\tSM:${sample_id}" \
                "$REF" "$trim_r1" "$trim_r2" \
                2> "$align_log" \
                | samtools sort -@ "${THREADS}" -T "$sort_tmp" -o "$bam" -
        else
            bwa mem -t "${THREADS}" \
                -R "@RG\tID:${sample_id}\tSM:${sample_id}" \
                "$REF" "$trim_r1" \
                2> "$align_log" \
                | samtools sort -@ "${THREADS}" -T "$sort_tmp" -o "$bam" -
        fi

        samtools index "$bam"

        if [[ ! -s "$bam" ]]; then
            echo "ERROR: ${sample_id}: alignment produced no BAM" >&2
            exit 68
        fi
        if [[ ! -s "${bam}.bai" ]]; then
            echo "ERROR: ${sample_id}: BAM index missing" >&2
            exit 68
        fi

        echo "stage_align: ${sample_id} OK" >&2
    done < <(tail -n +2 "$SAMPLESHEET")
}
