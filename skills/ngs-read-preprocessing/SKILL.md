---
name: ngs-read-preprocessing
description: Adapter trimming, quality filtering, and per-sample QC reporting with fastp.
---

# Skill: ngs-read-preprocessing

## Use When

- The user wants to trim adapters from raw sequencing reads.
- The user needs to filter low-quality reads or bases before downstream alignment.
- The user wants to generate clean FASTQ files suitable for alignment or assembly.
- The user needs a per-sample HTML QC report showing before/after statistics.
- The user wants to perform polyG or polyX tail trimming for NextSeq/NovaSeq platforms.
- The user needs to apply minimum read length filtering after trimming.

## Inputs

- Required:
  - Input FASTQ R1 (`-i FILE`) — single-end read file or forward reads for paired-end.
- Optional:
  - Input FASTQ R2 (`-I FILE`) — reverse reads for paired-end sequencing.
  - `--outdir DIR` — Output directory (default: `fastp_results`).
  - `--threads N` — Number of worker threads (default: 4).
  - `--min-qual N` — Minimum qualified quality phred value for sliding window filtering (default: 15).
  - `--min-len N` — Minimum read length after trimming (default: 36 bp).
  - `--polyg` — Enable polyG tail trimming (recommended for NextSeq/NovaSeq two-color chemistry).
  - Adapter sequences — auto-detected by default; user may supply explicit sequences via additional fastp flags.
  - Additional fastp flags passed through as extra arguments.

## Workflow

1. Validate that input FASTQ files exist and are readable.
2. Detect single-end vs. paired-end mode from the provided inputs (`-i` only vs. `-i` and `-I`).
3. Run fastp with adapter auto-detection (or user-specified adapter sequences if provided).
4. Apply quality filtering using a sliding window approach (default: Q15 qualified quality threshold).
5. Apply length filtering to discard reads shorter than the minimum length (default: 36 bp).
6. Enable polyG tail trimming for NextSeq/NovaSeq platforms if `--polyg` is specified.
7. Generate an HTML report and JSON statistics file with detailed before/after metrics.
8. Report summary: reads before/after filtering, bases before/after, Q20/Q30 rates, and adapter trimming rate.

## Output Contract

- **Cleaned FASTQ file(s)** — Trimmed and filtered reads (`<sample>_trimmed.fastq.gz`; R1 and R2 for paired-end).
- **fastp HTML report** — Per-sample visual QC summary (`<sample>_fastp.html`).
- **fastp JSON report** — Machine-readable statistics (`<sample>_fastp.json`).
- **Summary statistics** — Reads in/out, bases in/out, Q20/Q30 rates before and after filtering, adapter detection/trimming rate.

## Limits

- fastp must be installed and available on `$PATH`.
- fastp is single-threaded by default; use `-w` / `--threads` to enable multi-threading (up to 16 threads).
- This skill does not perform read alignment; use `genome-read-alignment` or `rnaseq-read-alignment` for that purpose.
- This skill does not aggregate QC across multiple samples; use `ngs-quality-control` for multi-sample QC aggregation with MultiQC.
- UMI processing is supported by fastp but is not enabled by default; pass `--umi` and related flags as extra arguments if needed.
- Interleaved FASTQ input is not supported by the wrapper script; use fastp directly for interleaved input.
- Common failure cases:
  - Paired-end FASTQ files with mismatched read counts causing fastp to abort.
  - Incorrect adapter sequences provided, leading to untrimmed reads.
  - Disk full during output writing, producing truncated FASTQ files.
