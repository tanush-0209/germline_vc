## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

## The pushed image
docker.io/tanush0209/variant-call@sha256:169eb952ab677087bf197703409f39ff683878727fa46fdd9dc166ecca067aaa

To rerun this in a year: pull the pushed image by its digest under "The pushed
image" — not the tag 1.0, which could be repointed at a different build by
then. That one line gets back the exact same bytes that produced this week's
cohort.filtered.vcf.gz, regardless of what the base image or bioconda's
channels look like at that point. The base image's own digest, and the
"Versions pinned" list, exist as a record of what went into the build and are
only needed if the pushed image is ever lost from the registry and has to be
rebuilt from containers/Dockerfile from scratch — in which case bioconda may
have moved the pinned tool versions forward in a way the Dockerfile's
`=version` pins do not fully protect against for their own transitive
dependencies (as section 3 of the demo measured: pinning samtools=1.21 still
let htslib drift between builds two weeks apart).
