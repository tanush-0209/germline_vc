stage_analyze() {
    local merge_dir="${OUTDIR}/merge"
    local analyze_dir="${OUTDIR}/analyze"
    mkdir -p "$analyze_dir"

    local in_vcf="${merge_dir}/cohort.vcf.gz"
    local filtered_vcf="${analyze_dir}/cohort.filtered.vcf.gz"

    gatk VariantFiltration \
        -R "$REF" \
        -V "$in_vcf" \
        -O "$filtered_vcf" \
        --filter-expression "QD < 2.0"  --filter-name "QD2" \
        --filter-expression "FS > 60.0" --filter-name "FS60" \
        --filter-expression "MQ < 40.0" --filter-name "MQ40" \
        --filter-expression "SOR > 3.0" --filter-name "SOR3" \
        2>> "${analyze_dir}/variantfiltration.log"

    if [[ ! -s "$filtered_vcf" ]]; then
        echo "ERROR: stage_analyze: no filtered VCF produced" >&2
        exit 72
    fi
    if [[ ! -s "${filtered_vcf}.tbi" ]]; then
        echo "ERROR: stage_analyze: filtered VCF index missing" >&2
        exit 72
    fi

    echo "stage_analyze: filtered VCF OK" >&2
}

