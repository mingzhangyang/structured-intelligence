---
name: wgs-variant-calling
description: End-to-end WGS/WES variant calling pipeline from raw FASTQ to annotated variants.
---

# Workflow: WGS/WES Variant Calling

## Overview

This workflow processes raw whole-genome or whole-exome sequencing data through quality control, alignment, variant calling, filtering, and annotation. Each step corresponds to a registered skill.

## Pipeline Steps

```
FASTQ → ngs-quality-control → ngs-read-preprocessing → genome-read-alignment
       → genome-alignment-qc → genome-variant-calling → genome-variant-filtering
       → genome-variant-annotation → Annotated VCF
```

### Step 1: Raw Read QC

**Skill**: `ngs-quality-control`

Assess raw FASTQ quality with FastQC. Aggregate reports with MultiQC. Identify adapter contamination, quality drop-off, GC bias, and duplication before trimming.

**Key decision**: If quality is uniformly high and no adapters are detected, trimming may be skipped (rare in practice).

### Step 2: Read Preprocessing

**Skill**: `ngs-read-preprocessing`

Trim adapters and filter low-quality reads with fastp. Enable polyG trimming for NovaSeq/NextSeq data. Verify ≥85% reads surviving with mean quality ≥Q30.

**Input**: Raw FASTQ from sequencer.
**Output**: Trimmed FASTQ for alignment.

### Step 3: Read Alignment

**Skill**: `genome-read-alignment`

Align trimmed reads to the reference genome with BWA-MEM2. Sort, index, and mark duplicates. Add read group information for downstream GATK compatibility.

**Key parameters**:
- Reference: GRCh38 analysis set (recommended) or T2T-CHM13.
- Read groups: must include ID, SM, PL, LB, PU.

**Input**: Trimmed FASTQ + indexed reference.
**Output**: Sorted, deduplicated BAM + index.

### Step 4: Alignment QC

**Skill**: `genome-alignment-qc`

Assess alignment quality: mapping rate, duplicate rate, coverage depth and uniformity, insert size. For WES, calculate on-target rate using the capture BED file.

**Pass criteria** (see knowledge/sources/genomics/quality-thresholds.md):
- Mapping rate ≥ 95%
- Duplicate rate < 15% (WGS) / < 20% (WES)
- Mean coverage ≥ 30× (WGS germline) / ≥ 50× on-target (WES)

**Key decision**: Samples failing QC should be flagged for re-sequencing or excluded.

### Step 5: Variant Calling

**Skill**: `genome-variant-calling`

Call SNVs and indels with GATK HaplotypeCaller (default) or DeepVariant. For cohort studies, use GVCF mode and joint genotyping.

**WES note**: Provide the capture BED file as intervals to restrict calling.

**Input**: Deduplicated BAM + reference.
**Output**: Raw VCF or gVCF.

### Step 6: Variant Filtering

**Skill**: `genome-variant-filtering`

Filter raw calls to remove low-confidence variants. Use GATK hard filters for small sample sets or VQSR for cohorts ≥30 exomes / ≥1 WGS.

**GATK hard filter thresholds** (SNPs): QD<2, FS>60, MQ<40, MQRankSum<-12.5, ReadPosRankSum<-8.

**Input**: Raw VCF + reference.
**Output**: Filtered VCF with PASS/filter labels.

### Step 7: Variant Annotation

**Skill**: `genome-variant-annotation`

Annotate filtered variants with gene impact (SnpEff or VEP), population frequencies (gnomAD), and clinical significance (ClinVar).

**Input**: Filtered VCF.
**Output**: Annotated VCF + summary report.

## WES-Specific Notes

- Provide capture kit BED file at alignment QC (on-target rate), variant calling (intervals), and filtering steps.
- Expect Ti/Tv ratio 2.8–3.3 for WES (vs 2.0–2.1 for WGS).
- On-target rate should be ≥70%.

## Shared References

- [File Formats](../../knowledge/sources/genomics/file-formats.md)
- [Reference Genomes](../../knowledge/sources/genomics/reference-genomes.md)
- [Quality Thresholds](../../knowledge/sources/genomics/quality-thresholds.md)
