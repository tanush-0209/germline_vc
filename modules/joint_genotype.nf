process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.vcf.gz', emit: vcf
    path 'cohort.vcf.gz.tbi', emit: tbi

    script:
    """
    args=()
    for f in *.g.vcf.gz; do
        args+=(-V "\$f")
    done
    gatk CombineGVCFs -R ${ref} "\${args[@]}" -O cohort.g.vcf.gz
    gatk GenotypeGVCFs -R ${ref} -V cohort.g.vcf.gz -L ${params.region} -O cohort.vcf.gz
    """
}
