---
name: metagenome-binning
description: Recover metagenome-assembled genomes (MAGs) from contigs using MetaBAT2, refine with DAS Tool, and assess quality with CheckM2.
---

# Skill: metagenome-binning

## Use When

- The user wants to recover individual microbial genomes from assembled metagenomic contigs.
- The user needs MAG quality assessment (completeness, contamination).
- The user wants to refine bins from multiple binners with DAS Tool.
- The user needs MIMAG-standard quality classifications for recovered genomes.

## Inputs

- Required:
  - Assembled contigs FASTA file.
  - BAM file of reads mapped back to contigs (for coverage calculation).
- Optional:
  - `--das-tool` — Enable DAS Tool refinement using multiple binner results.
  - `--min-contig N` — Minimum contig length for binning in bp (default: 1500).
  - `--threads N` — Number of threads (default: 4).
  - `--outdir DIR` — Output directory (default: `binning_results`).
  - `--checkm2-db PATH` — Path to CheckM2 database.

## Workflow

1. Calculate contig coverage depth with MetaBAT2's `jgi_summarize_bam_contig_depths`.
2. Run MetaBAT2 for initial binning.
3. Optionally run additional binners (MaxBin2, CONCOCT) for DAS Tool refinement.
4. If multiple binners used: run DAS Tool to select the best non-redundant bin set.
5. Run CheckM2 `predict` on the final bin set for completeness and contamination estimates.
6. Classify bins by MIMAG standards: high-quality (>=90% complete, <5% contamination), medium-quality (>=50%, <10%), low-quality (below thresholds).
7. Report: number of bins, quality distribution, total high/medium/low quality MAGs.

## Output Contract

- **MAG FASTA files** — One FASTA file per bin (`<outdir>/bins/<bin_id>.fa`).
- **CheckM2 quality report** — Completeness and contamination per bin (`<outdir>/checkm2/quality_report.tsv`).
- **Bin quality summary** — Per-bin completeness, contamination, N50, genome size, and MIMAG classification (`<outdir>/bin_summary.txt`).

## Limits

- MetaBAT2 and CheckM2 must be installed and available on `$PATH`.
- CheckM2 requires a pre-downloaded database (approximately 3 GB).
- DAS Tool requires results from multiple binners as input; it is optional but recommended.
- Assembly must have sufficient depth for binning (>10x per genome is recommended).
- Contigs shorter than 1500 bp are typically excluded from binning.
- MIMAG quality standards: high-quality draft (>=90% completeness, <5% contamination), medium-quality draft (>=50% completeness, <10% contamination).
- Common failure cases:
  - BAM file not sorted or indexed, causing `jgi_summarize_bam_contig_depths` to fail.
  - CheckM2 database not downloaded or path not set, preventing quality assessment.
  - Insufficient sequencing depth (<10x per genome) producing fragmented or empty bins.
