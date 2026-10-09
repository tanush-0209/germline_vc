process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam")

    script:
    if (meta.single_end)
        """
        bwa mem -t ${task.cpus} \\
            -R "@RG\\tID:${meta.id}\\tSM:${meta.id}" \\
            ${ref} ${reads} \\
            | samtools sort -@ ${task.cpus} -o ${meta.id}.sorted.bam -
        """
    else
        """
        bwa mem -t ${task.cpus} \\
            -R "@RG\\tID:${meta.id}\\tSM:${meta.id}" \\
            ${ref} ${reads[0]} ${reads[1]} \\
            | samtools sort -@ ${task.cpus} -o ${meta.id}.sorted.bam -
        """
}
