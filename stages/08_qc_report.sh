stage_qc_report() {
    local qc_report_dir="${OUTDIR}/qc_report"
    mkdir -p "$qc_report_dir"

    multiqc "$OUTDIR" -o "$qc_report_dir" -f \
        2>> "${qc_report_dir}/multiqc.log"

    if [[ ! -s "${qc_report_dir}/multiqc_report.html" ]]; then
        echo "ERROR: stage_qc_report: MultiQC produced no report" >&2
        exit 73
    fi

    echo "stage_qc_report: MultiQC report OK" >&2
}
