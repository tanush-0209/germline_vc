process FASTQC {
    tag "${meta.id}"
    container params.containers.fastqc

    input:
    tuple val(meta), path(reads)

    output:
    path "fastqc_${meta.id}"

    script:
    """
    mkdir fastqc_${meta.id}
    fastqc -t ${task.cpus} -o fastqc_${meta.id} ${reads}
    """
}
