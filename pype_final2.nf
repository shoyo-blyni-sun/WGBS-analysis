#!/usr/bin/env nextflow
nextflow.enable.dsl=2

//Описание процессов
process FASTQC {
    tag "$sample"
    publishDir "results/fastqc", mode: 'copy'

    input:
    tuple val(sample), path(fastq1), path(fastq2)   
// теперь два файла

    output:
    path "*.html", emit: html
    path "*.zip", emit: zip

    script:
    """
    fastqc ${fastq1} ${fastq2} -o .   
    """
}

process ALIGN {
    tag "$sample"
    publishDir "results/align", mode: 'copy'

    input: 
    tuple val(sample), path(fastq1), path(fastq2)
    path genome_dir

    output:
    tuple val(sample), path("*bt2_PE_report.txt"), emit: report
    tuple val(sample), path("*_bismark_bt2_pe.bam"), emit: bam_proc

    script:
    """
    bismark --bowtie2 --parallel 3 --genome ${genome_dir} -o . -1 ${fastq1} -2  ${fastq2}
    """
//тут в genome_dir уже лежат проиндексированные файлы

}


process DeDUPLICATE {
    tag "$sample"
    publishDir "results/dedup", mode: 'copy'

    input:
    tuple val(sample), path (bam_file)

    output:
    tuple val(sample), path("*_bismark_bt2_pe.deduplicated.bam"), emit: bam_dedup
    tuple val(sample), path("*_bismark_bt2_pe.deduplication_report.txt"), emit: report
    
    script:
    """
    bismark dedup -p --bam ${bam_file}
    """
}

process METH_CALL {
    tag "$sample"
    publishDir "results/meth_call", mode: 'copy'

    input:
    tuple val(sample), path(bam_dedup_file)

    output:
    tuple val(sample), path("*_pe.deduplicated.txt"), emit: bam_dedup_txt
    tuple val(sample), path("*_pe.deduplicated.bedGraph.gz"), emit: bedgraph
    tuple val(sample), path("*_pe.deduplicated.bismark.cov.gz"),emit: cov
    tuple val(sample), path("*_pe.deduplicated_splitting_report.txt"), emit: split_report
    tuple val(sample), path("*_pe.deduplicated.M-bias.txt"), emit: mbias
    
    script:
    """
    bismark_methylation_extractor -p --bedGraph --buffer_size 30G ${bam_dedup_file}
    """
}

process REPORT {
    publishDir "results/report", mode: 'copy'

    input:
    tuple val(sample), path(bam), path(dedup), path(splitting), path(mbias)

    output:
    tuple val(sample), path("*_PE_report.html"), emit: report

    script:
    """
    bismark report \\
        --alignment_report ${bam} \\
        --dedup_report ${dedup} \\
        --splitting_report ${splitting} \\
        --mbias_report ${mbias}
    """
}


workflow {
    // 1. Читаем samplesheet (теперь три колонки)
    reads_ch = Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def sample = row.sample
            def fq1 = row.fastq_1
            def fq2 = row.fastq_2
            return tuple(sample, fq1, fq2) 
        }
        .view { "Sample: ${it[0]}, R1: ${it[1]}, R2: ${it[2]}" }


    // 2. FastQC
    FASTQC(reads_ch)

    genome_ch = Channel.value(params.genome_index)
    align_output = ALIGN(reads_ch, genome_ch)
    dedup = DeDUPLICATE(align_output.bam_proc)
    meth = METH_CALL(dedup.bam_dedup)

    ch_for_report = align_output.report
        .join( dedup.report )
        .join( meth.split_report )
        .join( meth.mbias )
    rep = REPORT(ch_for_report)
}

//развилку пока удалила, но нужно будет восстановить.
// нужно будет указать 
// # BAM есть
//nextflow run main.nf -entry withBam

//# BAM нет
//nextflow run main.nf -entry withAlign
