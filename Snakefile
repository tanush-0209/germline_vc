configfile: "config.yaml"

import csv
import os
import re

KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]
REF_DICT = os.path.splitext(REF)[0] + ".dict"

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) if names else "(?!)"


def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]
rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    log:
        "logs/fastqc/{sample}.log",
    container: IMAGES["fastqc"]
    shell:
        "mkdir -p {output} && fastqc -o {output} {input.reads} > {log} 2>&1"


rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "fastp -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2} "
        "-j {output.json} -h {output.html} 2> {log}"


rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "fastp -i {input.r1} -o {output.r1} "
        "-j {output.json} -h {output.html} 2> {log}"


rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
    output:
        "work/align/{sample}.sorted.bam",
    threads: 8
    log:
        "logs/bwa_mem/{sample}.log",
    container: IMAGES["bwa"]
    shell:
        r"""
        (bwa mem -t {threads} -R "@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}" {input.ref} {input.reads} \
            | samtools sort -@ {threads} -o {output} -) 2> {log}
        """


rule markduplicates:
    input:
        bam="work/align/{sample}.sorted.bam",
    output:
        bam="work/postprocess/{sample}.dedup.bam",
        bai="work/postprocess/{sample}.dedup.bam.bai",
        flagstat="work/postprocess/{sample}.flagstat.txt",
    log:
        "logs/markduplicates/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (gatk MarkDuplicates -I {input.bam} -O {output.bam} -M work/postprocess/{wildcards.sample}.dup_metrics.txt \
            && samtools index {output.bam} \
            && samtools flagstat {output.bam} > {output.flagstat}) 2> {log}
        """


rule haplotypecaller:
    input:
        bam="work/postprocess/{sample}.dedup.bam",
        bai="work/postprocess/{sample}.dedup.bam.bai",
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    params:
        region=config["region"],
    threads: 8
    log:
        "logs/haplotypecaller/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        "gatk HaplotypeCaller -R {input.ref} -I {input.bam} -O {output.gvcf} "
        "-L {params.region} -ERC GVCF --native-pair-hmm-threads {threads} 2> {log}"
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    params:
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
        region=config["region"],
    log:
        "logs/joint_genotype.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (gatk CombineGVCFs -R {input.ref} {params.variants} -O work/joint/cohort.g.vcf.gz \
            && gatk GenotypeGVCFs -R {input.ref} -V work/joint/cohort.g.vcf.gz -L {params.region} -O {output.vcf}) 2> {log}
        """


rule filter:
    input:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    log:
        "logs/filter.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (gatk VariantFiltration -R {input.ref} -V {input.vcf} -O {output.vcf} \
            --filter-expression "QD < 2.0"  --filter-name "QD2" \
            --filter-expression "FS > 60.0" --filter-name "FS60" \
            --filter-expression "MQ < 40.0" --filter-name "MQ40" \
            --filter-expression "SOR > 3.0" --filter-name "SOR3" \
        && printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table} \
        && bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}) 2> {log}
        """


rule multiqc:
    input:
        expand("work/fastqc/{sample}", sample=SAMPLES),
        expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        expand("work/postprocess/{sample}.flagstat.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "multiqc -q -f -o {OUT} {input} > {log} 2>&1"


PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
