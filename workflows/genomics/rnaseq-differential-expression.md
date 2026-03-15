---
name: rnaseq-differential-expression
description: RNA-seq differential expression pipeline from raw FASTQ to DE gene lists, with alignment-based and alignment-free paths.
---

# Workflow: RNA-seq Differential Expression

## Overview

This workflow processes RNA-seq data to identify differentially expressed genes between conditions. It supports two parallel paths: alignment-based counting and alignment-free quantification.

## Pipeline Steps

```
                                    ┌─ Path A: rnaseq-read-alignment → rnaseq-alignment-qc → rnaseq-read-counting ─┐
FASTQ → ngs-quality-control → ngs-read-preprocessing ─┤                                                                            ├─→ rnaseq-differential-expression
                                    └─ Path B: rnaseq-transcript-quantification ────────────────────────────────────┘
```

### Step 1: Raw Read QC

**Skill**: `ngs-quality-control`

Assess raw FASTQ quality with FastQC/MultiQC. RNA-seq-specific checks: verify expected GC distribution for the organism, check for rRNA adapter contamination.

### Step 2: Read Preprocessing

**Skill**: `ngs-read-preprocessing`

Trim adapters and filter low-quality reads with fastp. Standard parameters apply.

**Input**: Raw FASTQ.
**Output**: Trimmed FASTQ.

### Path A: Alignment-Based Counting

#### Step 3A: Splice-Aware Alignment

**Skill**: `rnaseq-read-alignment`

Align with STAR (recommended) or HISAT2. Use two-pass mode for novel junction discovery. Provide GTF annotation for splice junction database.

**Key parameters**:
- STAR genome index with GTF (sjdbGTFfile).
- Two-pass mode for novel junctions.
- `--quantMode GeneCounts` produces basic counts (STAR only).

**Input**: Trimmed FASTQ + genome index + GTF.
**Output**: Sorted BAM + alignment log.

#### Step 4A: Alignment QC

**Skill**: `rnaseq-alignment-qc`

Check strandedness, gene body coverage, rRNA rate, read distribution across features.

**Pass criteria** (see knowledge/sources/genomics/quality-thresholds.md):
- Uniquely mapped ≥ 60%
- rRNA < 10%
- Gene body coverage: uniform (flag 3' bias)

**Key decision**: Strandedness must be determined here and used correctly in counting step.

#### Step 5A: Read Counting

**Skill**: `rnaseq-read-counting`

Count reads per gene with featureCounts (recommended) or HTSeq-count. Match strandedness to library prep.

**Input**: Sorted BAM(s) + GTF.
**Output**: Gene-level count matrix.

### Path B: Alignment-Free Quantification

#### Step 3B: Transcript Quantification

**Skill**: `rnaseq-transcript-quantification`

Quantify transcripts with Salmon (recommended) or kallisto. Produces transcript-level TPM and counts.

**Advantages**: Faster, no genome alignment needed, bias correction (GC, sequence, positional).
**Note**: Use tximport in R to summarize transcript counts to gene level for DE analysis.

**Input**: Trimmed FASTQ + transcriptome index.
**Output**: Transcript-level quant files (quant.sf or abundance.tsv).

### Step 6: Differential Expression

**Skill**: `rnaseq-differential-expression`

Run statistical DE testing with DESeq2 (default) or edgeR. Accepts count matrix (Path A) or transcript quant directories via tximport (Path B).

**Key considerations**:
- Minimum 3 biological replicates per condition.
- Include batch in design formula if batch effects are present.
- Default thresholds: FDR < 0.05, |log2FC| > 1.

**Input**: Count matrix + sample metadata.
**Output**: DE results table, PCA, volcano, MA plot, heatmap.

## Choosing Between Path A and Path B

| Criterion | Path A (Alignment) | Path B (Alignment-free) |
|-----------|-------------------|------------------------|
| Speed | Slower (STAR alignment) | Faster (Salmon/kallisto) |
| Novel junctions | Yes (two-pass STAR) | No |
| Isoform resolution | Limited | Yes (transcript-level) |
| Visualization (IGV) | Yes (BAM) | No |
| Recommended for | Standard DE + downstream | Large cohorts, quick DE |

## Shared References

- [File Formats](../../knowledge/sources/genomics/file-formats.md)
- [Reference Genomes](../../knowledge/sources/genomics/reference-genomes.md)
- [Quality Thresholds](../../knowledge/sources/genomics/quality-thresholds.md)
- [R Environment Setup](../../knowledge/sources/genomics/r-environment-setup.md)
