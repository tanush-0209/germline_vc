#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -o logs/pull-%j.out

set -euo pipefail
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p /scratch/${USER}/containers
apptainer pull /scratch/${USER}/containers/variant-call.sif \
    docker://tanush0209/variant-call@sha256:169eb952ab677087bf197703409f39ff683878727fa46fdd9dc166ecca067aaa
