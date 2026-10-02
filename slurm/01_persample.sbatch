#!/bin/bash
#SBATCH --job-name=persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=16
#SBATCH --mem=10G
#SBATCH --time=00:30:00
#SBATCH --output=logs/persample_%A_%a.out
#SBATCH --export=NONE
#SBATCH --kill-on-invalid-dep=yes

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")

[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no such row" >&2; exit 64; }

module load miniconda3/25.9.1
source activate "${CONDA_ENV}"

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}" quantify
