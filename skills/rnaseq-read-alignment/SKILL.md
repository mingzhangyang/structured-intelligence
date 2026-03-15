---
name: rnaseq-read-alignment
description: Splice-aware alignment of RNA-seq reads to a reference genome using STAR or HISAT2.
---

# Skill: RNA-seq Read Alignment

## Use When

- User needs splice-aware alignment for RNA-seq data
- User wants to produce genome-aligned BAMs for downstream counting
- User needs two-pass STAR alignment for novel junction discovery
- User wants to compare STAR vs HISAT2 aligners

## Inputs

- Required:
  - Trimmed FASTQ file(s) (single-end or paired-end)
  - Reference genome index (STAR genome directory or HISAT2 index prefix)
- Optional:
  - Aligner choice: `star` or `hisat2` (default: `star`)
  - GTF annotation file (for STAR splice junction database)
  - Number of threads (default: 4)
  - Output directory (default: `./alignment_output`)
  - Two-pass mode for STAR (enables novel junction discovery)
  - Maximum intron length

## Workflow

1. Validate that the genome index exists for the chosen aligner.
2. If STAR: run STAR with `--quantMode GeneCounts` (also produces per-gene counts) and `--outSAMtype BAM SortedByCoordinate`.
3. If STAR two-pass: run first pass for junction discovery, generate a new genome index incorporating discovered junctions, then run the second pass.
4. If HISAT2: run with `--dta` flag (downstream transcriptome assembly compatible), pipe output to `samtools sort` for coordinate-sorted BAM.
5. Index the output BAM with `samtools index`.
6. Report alignment statistics: total reads, uniquely mapped reads, multi-mapped reads, unmapped reads, splice junctions detected.

## Output Contract

- Sorted BAM file (`Aligned.sortedByCoord.out.bam` for STAR, `aligned.sorted.bam` for HISAT2)
- BAM index (`.bai`)
- Alignment log/summary (`Log.final.out` for STAR, `hisat2_summary.txt` for HISAT2)
- STAR gene counts file (`ReadsPerGene.out.tab`, if STAR)
- Splice junction file (`SJ.out.tab` for STAR)

## Limits

- STAR requires approximately 32 GB RAM for the human genome; HISAT2 is lighter at approximately 8 GB.
- Genome index must be pre-built before running this skill.
- STAR two-pass mode is slower but recommended for novel junction discovery.
- STAR and HISAT2 must be installed and available on PATH.
- Common failure cases:
  - STAR genome index built with an incompatible STAR version, causing segfault or load error.
  - Insufficient RAM for STAR genome loading (32 GB for human; job killed by OOM).
  - GTF annotation file missing or mismatched with the genome build, producing zero splice junctions.
