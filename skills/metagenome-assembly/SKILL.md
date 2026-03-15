---
name: metagenome-assembly
description: De novo assembly of metagenomic contigs from short reads using MEGAHIT or metaSPAdes.
---

# Skill: metagenome-assembly

## Use When

- The user wants to assemble metagenomic reads into contigs for downstream analysis.
- The user needs contigs for downstream binning and gene prediction.
- The user wants to compare assemblers (MEGAHIT vs metaSPAdes).
- The user has sufficient compute resources for de novo metagenomic assembly.

## Inputs

- Required:
  - Host-depleted FASTQ file(s) (`.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`).
- Optional:
  - `--assembler STR` — Assembler to use: `megahit` or `metaspades` (default: `megahit`).
  - `--threads N` — Number of threads (default: 4).
  - `--memory N` — Memory limit in GB (default: 16).
  - `--min-length N` — Minimum contig length in bp (default: 1000).
  - `--kmer-sizes STR` — Comma-separated k-mer sizes for metaSPAdes (e.g., `21,33,55,77`).
  - `--outdir DIR` — Output directory (default: `assembly_results`).

## Workflow

1. If MEGAHIT: run `megahit` with `--min-contig-len`, `--num-cpu-threads`, `-m` memory.
2. If metaSPAdes: run `spades.py --meta` with `-k` kmer sizes, `-t` threads, `-m` memory.
3. Filter contigs by minimum length.
4. Generate assembly statistics: total contigs, total length, N50, L50, largest contig, GC content.
5. Report assembly summary.

## Output Contract

- **Contigs FASTA** — Assembled contigs filtered by minimum length (`<outdir>/contigs_min<N>bp.fasta`).
- **Assembly statistics** — N50, L50, total length, contig count, largest contig, GC percentage (`<outdir>/assembly_stats.txt`).

## Limits

- metaSPAdes requires significantly more memory than MEGAHIT (100-500 GB vs 10-50 GB for human gut metagenomes).
- MEGAHIT is faster and more memory-efficient; recommended as the default for most samples.
- Minimum contig length of 1000 bp is recommended for downstream binning.
- Assembly quality depends heavily on sequencing depth and community complexity.
- MEGAHIT and metaSPAdes (SPAdes) must be installed and available on `$PATH`.
- This skill does not perform scaffolding; output is contigs only.
- Common failure cases:
  - metaSPAdes running out of memory on complex or deeply sequenced samples.
  - MEGAHIT crashing due to insufficient disk space for intermediate k-mer graph files.
  - Input reads still containing host contamination, inflating assembly size with host contigs.
