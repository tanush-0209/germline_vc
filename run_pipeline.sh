#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- argument parsing ----
SAMPLESHEET=""
OUTDIR=""
LAST_STAGE="publish"   # default: run everything

while [[ $# -gt 0 ]]; do
    case "$1" in
        --samplesheet) SAMPLESHEET="$2"; shift 2 ;;
        --outdir)      OUTDIR="$2";      shift 2 ;;
        --to)          LAST_STAGE="$2";  shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$SAMPLESHEET" || -z "$OUTDIR" ]]; then
    echo "usage: $0 --samplesheet FILE --outdir DIR [--to STAGE]" >&2
    exit 2
fi

mkdir -p "$OUTDIR"

# ---- config: only these two names appear anywhere in the stages ----
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}

# ---- stage functions go here (stage_validate, stage_qc_raw, ...) ----
stage_validate() {
    local problems=0
    local sample_ids=()

    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
        sample_ids+=("$sample_id")

        # --- R1 must exist and be an intact gzip file ---
        if [[ ! -f "$r1_fastq" ]]; then
            echo "ERROR: ${sample_id}: r1_fastq not found: ${r1_fastq}" >&2
            problems=$(( problems + 1 ))
        elif ! gzip -t "$r1_fastq" 2>/dev/null; then
            echo "ERROR: ${sample_id}: r1_fastq is truncated or not valid gzip: ${r1_fastq}" >&2
            problems=$(( problems + 1 ))
        fi

        # --- library_type must agree with whether r2_fastq is present ---
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

    # --- no sample_id may repeat ---
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

stage_qc_raw() {
    local qc_dir="${OUTDIR}/qc_raw"
    mkdir -p "$qc_dir"

    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
        if [[ "$library_type" == "paired" ]]; then
            fastqc -o "$qc_dir" "$r1_fastq" "$r2_fastq" 2>> "${qc_dir}/${sample_id}.fastqc.log"
        else
            fastqc -o "$qc_dir" "$r1_fastq" 2>> "${qc_dir}/${sample_id}.fastqc.log"
        fi

        # --- did FastQC actually produce a report for R1? ---
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

stage_trim() {
    local trim_dir="${OUTDIR}/trim"
    mkdir -p "$trim_dir"

    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
        local out_r1="${trim_dir}/${sample_id}_R1.trimmed.fastq.gz"
        local out_r2="${trim_dir}/${sample_id}_R2.trimmed.fastq.gz"
        local report_html="${trim_dir}/${sample_id}.fastp.html"
        local report_json="${trim_dir}/${sample_id}.fastp.json"

        if [[ "$library_type" == "paired" ]]; then
            fastp \
                -i "$r1_fastq" -I "$r2_fastq" \
                -o "$out_r1" -O "$out_r2" \
                -h "$report_html" -j "$report_json" \
                --thread "${THREADS:-4}" \
                2>> "${trim_dir}/${sample_id}.fastp.log"
        else
            fastp \
                -i "$r1_fastq" \
                -o "$out_r1" \
                -h "$report_html" -j "$report_json" \
                --thread "${THREADS:-4}" \
                2>> "${trim_dir}/${sample_id}.fastp.log"
        fi

        # --- check what came out ---
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

stage_align() {
    local align_dir="${OUTDIR}/align"
    mkdir -p "$align_dir"

    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
        local trim_r1="${OUTDIR}/trim/${sample_id}_R1.trimmed.fastq.gz"
        local trim_r2="${OUTDIR}/trim/${sample_id}_R2.trimmed.fastq.gz"
        local bam="${align_dir}/${sample_id}.sorted.bam"
        local align_log="${align_dir}/${sample_id}.bwa.log"

        if [[ "$library_type" == "paired" ]]; then
            bwa mem -t "${THREADS:-4}" \
                -R "@RG\tID:${sample_id}\tSM:${sample_id}" \
                "$REF" "$trim_r1" "$trim_r2" \
                2> "$align_log" \
                | samtools sort -@ "${THREADS:-4}" -o "$bam" -
        else
            bwa mem -t "${THREADS:-4}" \
                -R "@RG\tID:${sample_id}\tSM:${sample_id}" \
                "$REF" "$trim_r1" \
                2> "$align_log" \
                | samtools sort -@ "${THREADS:-4}" -o "$bam" -
        fi

        samtools index "$bam"

        # --- check what came out ---
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

stage_postprocess() {
    local align_dir="${OUTDIR}/align"
    local post_dir="${OUTDIR}/postprocess"
    mkdir -p "$post_dir"

    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
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

stage_quantify() {
    local post_dir="${OUTDIR}/postprocess"
    local vc_dir="${OUTDIR}/quantify"
    mkdir -p "$vc_dir"

    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
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

stage_merge() {
    local vc_dir="${OUTDIR}/quantify"
    local merge_dir="${OUTDIR}/merge"
    mkdir -p "$merge_dir"

    local combined_gvcf="${merge_dir}/cohort.g.vcf.gz"
    local genotyped_vcf="${merge_dir}/cohort.vcf.gz"

    # --- build -V arguments, one per sample's GVCF ---
    local gvcf_args=()
    while IFS=, read -r sample_id condition replicate library_type r1_fastq r2_fastq; do
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



# ---- the driver ----
STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

n=0
for stage in "${STAGES[@]}"; do
    echo "===== stage ${n} : ${stage} =====" >&2
    "stage_${stage}"
    [[ "$stage" == "$LAST_STAGE" ]] && break
    n=$(( n + 1 ))
done
