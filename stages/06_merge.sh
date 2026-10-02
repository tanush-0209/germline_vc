stage_merge() {
    local vc_dir="${OUTDIR}/quantify"
    local merge_dir="${OUTDIR}/merge"
    mkdir -p "$merge_dir"

    local combined_gvcf="${merge_dir}/cohort.g.vcf.gz"
    local genotyped_vcf="${merge_dir}/cohort.vcf.gz"

    load_header "$SAMPLESHEET"

    local gvcf_args=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sample_id
        sample_id=$(get_field "$line" sample_id)
        gvcf_args+=("-V" "${vc_dir}/${sample_id}.g.vcf.gz")
    done < <(tail -n +2 "$SAMPLESHEET")

    gatk CombineGVCFs \
        -R "$REF" \
        "${gvcf_args[@]}" \
        -O "$combined_gvcf" \
        2>> "${merge_dir}/combine.log"

    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "$combined_gvcf" \
        -O "$genotyped_vcf" \
        -L "$REGION" \
        2>> "${merge_dir}/genotype.log"

    if [[ ! -s "$genotyped_vcf" ]]; then
        echo "ERROR: stage_merge: no joint-genotyped VCF produced" >&2
        exit 71
    fi
    if [[ ! -s "${genotyped_vcf}.tbi" ]]; then
        echo "ERROR: stage_merge: joint-genotyped VCF index missing" >&2
        exit 71
    fi

    echo "stage_merge: cohort VCF OK" >&2
}
