---
name: metagenomics-shotgun
description: Shotgun metagenomics pipeline from raw FASTQ through host removal, taxonomic profiling, assembly, binning, and functional annotation.
---

# Workflow: Shotgun Metagenomics

## Overview

This workflow processes shotgun metagenomic sequencing data to characterize microbial community composition and function. It includes mandatory steps (QC, host removal, taxonomic profiling) and optional assembly-based steps (assembly, binning, functional annotation).

## Pipeline Steps

```
FASTQ → ngs-quality-control → ngs-read-preprocessing → metagenome-host-removal
       → metagenome-taxonomic-profiling
       → [optional: metagenome-assembly → metagenome-binning]
       → metagenome-functional-profiling
```

### Step 1: Raw Read QC

**Skill**: `ngs-quality-control`

Assess raw FASTQ quality with FastQC/MultiQC. Metagenomic-specific checks: unusual GC distributions may indicate host contamination or low-complexity libraries.

### Step 2: Read Preprocessing

**Skill**: `ngs-read-preprocessing`

Trim adapters and filter low-quality reads with fastp. Standard parameters apply. Consider more aggressive quality filtering for assembly (Q20).

**Input**: Raw FASTQ.
**Output**: Trimmed FASTQ.

### Step 3: Host Removal

**Skill**: `metagenome-host-removal`

Align reads to host genome (human: GRCh38) and extract unmapped pairs. Critical for clinical and human-associated samples.

**Target**: ≥95% host reads removed.

**Key decision**: For non-host-associated samples (e.g., soil, ocean), this step may be skipped or use a minimal reference.

**Input**: Trimmed FASTQ + host genome index.
**Output**: Host-depleted FASTQ.

### Step 4: Taxonomic Profiling

**Skill**: `metagenome-taxonomic-profiling`

Profile community composition with Kraken2/Bracken (default) or MetaPhlAn 4.

**Kraken2 + Bracken**: Fast, comprehensive, k-mer-based. Run Bracken for re-estimated species-level abundances.
**MetaPhlAn 4**: Marker-gene-based, higher precision at species level, smaller database.

**Input**: Host-depleted FASTQ.
**Output**: Taxonomic abundance profile, diversity metrics.

### Step 5 (Optional): Metagenomic Assembly

**Skill**: `metagenome-assembly`

Assemble reads into contigs with MEGAHIT (default, memory-efficient) or metaSPAdes (higher contiguity, more memory). Filter contigs ≥1000 bp.

**When to assemble**:
- Need to recover genomes (MAGs) from the community.
- Want gene-level functional annotation.
- Sufficient sequencing depth (>1 Gbp per sample recommended).

**When to skip**:
- Only taxonomic composition is needed.
- Very low sequencing depth.
- Time/compute constraints.

**Input**: Host-depleted FASTQ.
**Output**: Assembled contigs FASTA.

### Step 6 (Optional): Genome Binning

**Skill**: `metagenome-binning`

Recover MAGs from assembled contigs using MetaBAT2. Optionally refine with DAS Tool (combining multiple binners). Assess quality with CheckM2.

**Prerequisite**: Map reads back to contigs to generate BAM for coverage-based binning.

```bash
# Map reads back to contigs for coverage
bwa-mem2 index contigs.fa
bwa-mem2 mem -t 8 contigs.fa R1.fq.gz R2.fq.gz | samtools sort -o mapped.bam
samtools index mapped.bam
```

**MIMAG quality standards**:
- High-quality: ≥90% complete, <5% contamination, 23S/16S/5S rRNA, ≥18 tRNAs.
- Medium-quality: ≥50% complete, <10% contamination.

**Input**: Contigs FASTA + reads-to-contigs BAM.
**Output**: MAG FASTA files, CheckM2 quality report.

### Step 7: Functional Profiling

**Skill**: `metagenome-functional-profiling`

Annotate metabolic functions. Three approaches:

**Read-based (HUMAnN 3)**: Gene family and pathway abundance directly from reads. Produces MetaCyc pathway profiles. Best for comparing functional potential across samples.

**Gene prediction (Prokka)**: Predict and annotate genes from contigs or MAGs. Produces GFF, GenBank, protein FASTA.

**Ortholog assignment (eggNOG-mapper)**: Assign COG, KEGG, GO terms to predicted proteins. Broader functional categories.

**Input**: Host-depleted FASTQ (HUMAnN) or contigs/MAGs (Prokka, eggNOG).
**Output**: Pathway abundance tables, gene annotations.

## Analysis Strategy by Question

| Question | Required Steps | Optional Steps |
|----------|---------------|----------------|
| What's in my sample? | 1–4 | — |
| What can my community do? | 1–4, 7 (HUMAnN) | — |
| Can I recover genomes? | 1–6 | 7 (Prokka/eggNOG on MAGs) |
| Full characterization | 1–7 (all) | — |

## Shared References

- [File Formats](../../knowledge/sources/genomics/file-formats.md)
- [Reference Genomes](../../knowledge/sources/genomics/reference-genomes.md)
- [Quality Thresholds](../../knowledge/sources/genomics/quality-thresholds.md)
