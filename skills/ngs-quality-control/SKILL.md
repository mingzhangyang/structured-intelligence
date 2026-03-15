---
name: ngs-quality-control
description: Raw read quality assessment with FastQC and multi-sample report aggregation with MultiQC.
---

# Skill: ngs-quality-control

## Use When

- The user wants to assess raw FASTQ read quality before downstream analysis.
- The user needs per-sample QC reports generated with FastQC.
- The user wants to aggregate QC results across multiple samples into a single summary with MultiQC.
- The user wants to check for adapter contamination, per-base quality drop-off, GC bias, or duplication levels before proceeding to trimming or alignment.

## Inputs

- Required:
  - FASTQ file(s) or a directory containing FASTQ files (`.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`).
- Optional:
  - `--outdir DIR` — Output directory for reports (default: `fastqc_results`).
  - `--threads N` — Number of parallel threads for FastQC (default: 4).
  - `--multiqc-config FILE` — Custom MultiQC configuration file for report customization.
  - Additional FastQC modules to disable (pass via extra flags).

## Workflow

1. Validate that input FASTQ files exist and are readable.
2. Run FastQC on each FASTQ file, supporting parallel execution via `--threads`.
3. Collect all FastQC output directories (HTML reports and ZIP archives).
4. Run MultiQC to aggregate individual FastQC reports into a single HTML summary.
5. Parse key metrics from the results: per-base sequence quality, adapter content, sequence duplication levels, and per-sequence GC distribution.
6. Flag samples that fail critical quality thresholds (refer to `knowledge/sources/genomics/quality-thresholds.md` for threshold definitions).
7. Report summary statistics and the locations of the generated HTML reports.

## Output Contract

- **FastQC HTML report** — One per input FASTQ file (`<sample>_fastqc.html`).
- **FastQC ZIP archive** — One per input FASTQ file (`<sample>_fastqc.zip`), containing raw data and images.
- **MultiQC HTML report** — Aggregated summary at `<outdir>/multiqc/multiqc_report.html`.
- **Summary table** — Pass/Warn/Fail status per FastQC module per sample.
- **Flagged samples list** — Samples failing critical thresholds, with the specific modules that triggered the flag.

## Limits

- FastQC and MultiQC must be installed and available on `$PATH`.
- FastQC requires approximately 250 MB of memory per thread.
- This skill does not perform adapter trimming or quality filtering; use `ngs-read-preprocessing` for that purpose.
- MultiQC aggregation requires that all FastQC outputs are in a single directory tree.
- Very large cohorts (hundreds of samples) may require increased memory for MultiQC.
- Common failure cases:
  - Input files not in FASTQ format or corrupted gzip archives.
  - Insufficient disk space for FastQC output (HTML + ZIP per sample).
  - MultiQC version mismatch causing module parsing errors on newer FastQC output.
