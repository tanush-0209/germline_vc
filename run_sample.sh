#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# usage: run_sample.sh <samplesheet> <outdir> <sample_id> [last-stage]
SAMPLESHEET="${1:?usage: run_sample.sh SAMPLESHEET OUTDIR SAMPLE_ID [LAST_STAGE]}"
OUTDIR="${2:?usage: run_sample.sh SAMPLESHEET OUTDIR SAMPLE_ID [LAST_STAGE]}"
SAMPLE_FILTER="${3:?usage: run_sample.sh SAMPLESHEET OUTDIR SAMPLE_ID [LAST_STAGE]}"
LAST_STAGE="${4:-quantify}"
export SAMPLE_FILTER

# --- this entry point only runs stages 0-5; cohort stages are refused ---
case "$LAST_STAGE" in
    merge|analyze|qc_report|publish)
        echo "ERROR: run_sample.sh only runs stages 0-5 for one sample; ${LAST_STAGE} is a cohort stage and belongs to run_pipeline.sh" >&2
        exit 75
        ;;
esac

mkdir -p "$OUTDIR"

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do
    source "$f"
done

STAGES=(validate qc_raw trim align postprocess quantify)

n=0
for stage in "${STAGES[@]}"; do
    echo "===== stage ${n} : ${stage} (sample ${SAMPLE_FILTER}) =====" >&2
    "stage_${stage}"
    [[ "$stage" == "$LAST_STAGE" ]] && break
    n=$(( n + 1 ))
done
