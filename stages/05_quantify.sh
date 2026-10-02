stage_quantify() {
    local post_dir="${OUTDIR}/postprocess"
    local vc_dir="${OUTDIR}/quantify"
    mkdir -p "$vc_dir"

    load_header "$SAMPLESHEET"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id
        sample_id=$(get_field "$line" sample_id)
        [[ -n "${SAMPLE_FILTER:-}" && "$sample_id" != "$SAMPLE_FILTER" ]] && continue

        local dedup_bam="${post_dir}/${sample_id}.dedup.bam"
        local gvcf="${vc_dir}/${sample_id}.g.vcf.gz"

        gatk HaplotypeCaller \
            -R "$REF" \
            -I "$dedup_bam" \
            -O "$gvcf" \
            -L "$REGION" \
            -ERC GVCF \
            2>> "${vc_dir}/${sample_id}.haplotypecaller.log"

        if [[ ! -s "$gvcf" ]]; then
            echo "ERROR: ${sample_id}: HaplotypeCaller produced no GVCF" >&2
            exit 70
        fi
        if [[ ! -s "${gvcf}.tbi" ]]; then
            echo "ERROR: ${sample_id}: GVCF index missing" >&2
            exit 70
        fi

        echo "stage_quantify: ${sample_id} OK" >&2
    done < <(tail -n +2 "$SAMPLESHEET")
}
