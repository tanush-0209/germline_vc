stage_publish() {
    local results_dir="${OUTDIR}/results"
    mkdir -p "$results_dir"

    cp "${OUTDIR}/analyze/cohort.filtered.vcf.gz"     "${results_dir}/"
    cp "${OUTDIR}/analyze/cohort.filtered.vcf.gz.tbi" "${results_dir}/"
    cp "${OUTDIR}/qc_report/multiqc_report.html"      "${results_dir}/"

    bash "${HERE}/lib/write_manifest.sh" "$results_dir" "$SAMPLESHEET" "$REF" "$REGION"

    if [[ ! -s "${results_dir}/manifest.json" ]]; then
        echo "ERROR: stage_publish: manifest.json was not written" >&2
        exit 74
    fi

    echo "stage_publish: results published to ${results_dir}" >&2
}
