---
name: genome-alignment-qc
description: Assess alignment quality with coverage depth, mapping rates, insert size, and on-target metrics using samtools, mosdepth, and picard.
---

# Skill: genome-alignment-qc

## Use When

- User wants to evaluate BAM quality before variant calling.
- User needs to assess coverage depth and uniformity across the genome or target regions.
- User wants to check mapping rate, duplication rate, and insert size distribution.
- User needs to calculate on-target rate for whole-exome sequencing (WES).
- User wants to compare QC metrics across samples to detect batch effects.

## Inputs

- Required:
  - BAM file with index (`.bam` + `.bai`).
- Optional:
  - Target BED file (for WES on-target metrics).
  - Reference FASTA (required for picard metrics).
  - Output directory (default: current directory).
  - Per-base coverage flag (enables mosdepth per-base output; default: off).

## Workflow

1. Run `samtools stats` and `samtools flagstat` for mapping summary.
2. Run `samtools idxstats` for per-chromosome read counts.
3. Run `mosdepth` for coverage distribution (genome-wide, or restricted to target BED).
4. If target BED provided: compute on-target rate and per-target coverage statistics.
5. Run `picard CollectInsertSizeMetrics` for insert size distribution.
6. Run `picard CollectAlignmentSummaryMetrics` for detailed alignment statistics.
7. Compile summary: mapping rate, duplicate rate, mean coverage, coverage uniformity (CV), median insert size, on-target rate (if WES).
8. Flag metrics outside recommended thresholds (see `knowledge/sources/genomics/quality-thresholds.md`).

## Output Contract

- `samtools stats` and `samtools flagstat` output files.
- `mosdepth` coverage files (`.mosdepth.global.dist.txt`, `.per-base.bed.gz` if enabled).
- Picard insert size metrics file and histogram.
- Picard alignment summary metrics file.
- Compiled QC summary with key metrics and threshold flags.

## Limits

- samtools, mosdepth, and picard must be installed and available on `$PATH`.
- mosdepth per-base output can be very large for WGS (~10 GB for 30x human).
- Picard requires a Java runtime (Java 8+).
- Reference FASTA is required for picard metrics but not for samtools/mosdepth.
- This skill reports metrics for a single BAM; multi-sample comparison is out of scope.
- Common failure cases:
  - BAM index (`.bai`) missing or out of date relative to the BAM file.
  - Target BED file using different chromosome naming convention than the BAM (e.g., `chr1` vs `1`).
  - Picard failing due to missing reference FASTA sequence dictionary (`.dict`).
