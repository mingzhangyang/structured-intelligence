---
name: metagenome-host-removal
description: Remove host-derived reads from metagenomic samples by aligning to a host reference genome and extracting unmapped pairs.
---

# Skill: metagenome-host-removal

## Use When

- The user has shotgun metagenomic reads contaminated with host DNA.
- The user wants to remove human, mouse, or other host reads before taxonomic or assembly analysis.
- The user needs to quantify the host contamination rate in a metagenomic sample.

## Inputs

- Required:
  - FASTQ file(s) — single-end or paired-end reads (`.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`).
  - Host reference genome index — pre-built Bowtie2 or BWA-MEM2 index.
- Optional:
  - `--aligner` — Aligner to use (`bowtie2` or `bwa-mem2`, default: `bowtie2`).
  - `--threads N` — Number of threads (default: 4).
  - `--outdir DIR` — Output directory (default: `host_removal_results`).
  - `--sensitivity` — Bowtie2 sensitivity preset (`--very-sensitive`, `--sensitive`; default: `--very-sensitive`).

## Workflow

1. Align reads to the host reference genome using Bowtie2 or BWA-MEM2.
2. Extract unmapped reads (`samtools view -f 4` for SE; `-f 12` for PE unmapped pairs).
3. Sort unmapped reads by name (`samtools sort -n`).
4. Convert back to FASTQ (`samtools fastq`).
5. Report: total reads, host reads removed, non-host reads retained, host contamination rate.

## Output Contract

- **Host-depleted FASTQ(s)** — One or two FASTQ files with host reads removed (`<outdir>/<sample>_hostdepleted_R1.fastq.gz`, `_R2.fastq.gz` for PE).
- **Host contamination summary** — Total reads, host reads, non-host reads, host contamination percentage.

## Limits

- Bowtie2 or BWA-MEM2 must be installed and available on `$PATH`.
- `samtools` must be installed and available on `$PATH`.
- Host genome index must be pre-built (use `bowtie2-build` or `bwa-mem2 index`).
- Human reference: GRCh38 (hg38) is recommended for human host removal.
- For clinical samples, host removal rate should be >95%; lower rates suggest index mismatch or sample issues.
- This skill does not build the host index; the user must provide a pre-built index path.
- Common failure cases:
  - Host genome index path incorrect or index files incomplete, causing aligner to abort.
  - Using the wrong host reference genome (e.g., mouse index for a human-derived sample).
  - Paired-end read extraction flags incorrect, producing orphan reads without mates.
