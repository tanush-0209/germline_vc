#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source conf/slurm.env

mkdir -p logs

ARRAY_RANGE="${1:-1-8}"

ARRAY_JOB=$(sbatch -p "${PARTITION}" -A "${ACCOUNT}" --array="${ARRAY_RANGE}" --parsable 01_persample.sbatch)
echo "array job: ${ARRAY_JOB}"

COHORT_JOB=$(sbatch -p "${PARTITION}" -A "${ACCOUNT}" \
    --dependency=afterok:"${ARRAY_JOB}" \
    --kill-on-invalid-dep=yes \
    --parsable 02_cohort.sbatch)
echo "cohort job: ${COHORT_JOB} (depends on ${ARRAY_JOB})"
