#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

SAMPLESHEET=""
OUTDIR=""
LAST_STAGE="publish"

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

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do
    source "$f"
done

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

n=0
for stage in "${STAGES[@]}"; do
    echo "===== stage ${n} : ${stage} =====" >&2
    "stage_${stage}"
    [[ "$stage" == "$LAST_STAGE" ]] && break
    n=$(( n + 1 ))
done
