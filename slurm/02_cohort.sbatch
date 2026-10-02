#!/bin/bash
#SBATCH --job-name=cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --output=logs/cohort_%j.out
#SBATCH --export=NONE
#SBATCH --kill-on-invalid-dep=yes

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

module load miniconda3/25.9.1
source activate "${CONDA_ENV}"

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

bash "${PIPELINE_DIR}/run_pipeline.sh" --samplesheet "${SAMPLESHEET}" --outdir "${RUN_ROOT}" --from merge --to publish
