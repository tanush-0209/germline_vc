#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

SAMPLESHEET=""
OUTDIR=""
FIRST_STAGE="validate"
LAST_STAGE="publish"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --samplesheet) SAMPLESHEET="$2"; shift 2 ;;
        --outdir)      OUTDIR="$2";      shift 2 ;;
        --from)        FIRST_STAGE="$2"; shift 2 ;;
        --to)          LAST_STAGE="$2";  shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$SAMPLESHEET" || -z "$OUTDIR" ]]; then
    echo "usage: $0 --samplesheet FILE --outdir DIR [--from STAGE] [--to STAGE]" >&2
    exit 2
fi

mkdir -p "$OUTDIR"

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do
    source "$f"
done

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

start_n=-1
end_n=-1
n=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$FIRST_STAGE" ]] && start_n=$n
    [[ "$stage" == "$LAST_STAGE" ]]  && end_n=$n
    n=$(( n + 1 ))
done

if (( start_n == -1 )); then
    echo "ERROR: unknown --from stage: ${FIRST_STAGE}" >&2
    exit 2
fi
if (( end_n == -1 )); then
    echo "ERROR: unknown --to stage: ${LAST_STAGE}" >&2
    exit 2
fi
if (( start_n > end_n )); then
    echo "ERROR: --from (${FIRST_STAGE}) comes after --to (${LAST_STAGE})" >&2
    exit 2
fi

n=0
for stage in "${STAGES[@]}"; do
    if (( n >= start_n && n <= end_n )); then
        echo "===== stage ${n} : ${stage} =====" >&2
        "stage_${stage}"
    fi
    (( n == end_n )) && break
    n=$(( n + 1 ))
done
