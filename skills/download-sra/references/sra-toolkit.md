# SRA Toolkit Reference

## Overview

The NCBI SRA Toolkit provides `prefetch`, `fasterq-dump`, and `vdb-validate` for downloading and converting SRA data to FASTQ format.

## Core Workflow

```bash
# 1. Download .sra file
prefetch --output-directory ./sra_cache SRR1234567

# 2. Convert to FASTQ (paired-end, split into R1 + R2 + unpaired)
fasterq-dump --split-3 --threads 8 --outdir ./fastq \
    ./sra_cache/SRR1234567/SRR1234567.sra

# 3. Compress
pigz -p 8 ./fastq/*.fastq

# 4. Validate
vdb-validate ./sra_cache/SRR1234567
```

## prefetch

| Flag | Meaning |
|------|---------|
| `--output-directory DIR` | Cache directory for .sra files |
| `--max-size SIZE` | Skip if file exceeds SIZE (e.g. `50G`) |
| `--ngc FILE` | dbGaP controlled-access token |
| `--progress` | Show progress bar |
| `-X SIZE` | Alias for `--max-size` |

## fasterq-dump

| Flag | Meaning |
|------|---------|
| `--split-3` | R1 + R2 + unpaired.fastq (recommended for PE) |
| `--split-files` | One file per read type (no unpaired merging) |
| `--outdir DIR` | Destination directory |
| `--threads N` | CPU threads (default 6) |
| `--temp DIR` | Temp directory (needs 6-10× FASTQ size) |
| `--skip-technical` | Drop technical reads (primers, barcodes) |
| `--include-technical` | Keep technical reads |

## Split Mode Comparison

| Mode | Single-end | Paired-end |
|------|-----------|-----------|
| `--split-3` | `SRR.fastq` | `SRR_1.fastq`, `SRR_2.fastq`, `SRR.fastq` (unpaired) |
| `--split-files` | `SRR_1.fastq` | `SRR_1.fastq`, `SRR_2.fastq`, `SRR_3.fastq` |
| (none) | `SRR.fastq` | `SRR.fastq` (interleaved) |

Use `--split-3` by default. Interleaved output is rarely what downstream tools expect.

## Disk Space Requirements

- `.sra` file: ~30–50% of final FASTQ size
- `fasterq-dump` temp space: 6–10× compressed FASTQ size
- Final gzipped FASTQ: 1×

Plan: for a 10 GB gzipped FASTQ pair, you need ~60–100 GB of temp space.

## SRA on AWS (Alternative)

Many SRA runs are available on AWS S3 as public data:

```bash
# Check availability
aws s3 ls s3://sra-pub-run-odp/sra/SRR1234567/ --no-sign-request

# Download .sra directly
aws s3 cp s3://sra-pub-run-odp/sra/SRR1234567/SRR1234567 \
    ./sra_cache/SRR1234567.sra --no-sign-request
```

This is faster than NCBI FTP for users with high AWS bandwidth or running on EC2.

## dbGaP Controlled Access

```bash
# Download the .ngc token from dbGaP project page, then:
prefetch --ngc /path/to/prjNNNNNN.ngc SRR1234567
```

## Common Gotchas

- `fasterq-dump` temp directory must be on the same filesystem as `--outdir`, or large enough independently.
- Do not run `fasterq-dump` on a directory of `.sra` files; run on one `.sra` at a time in a loop.
- SRX and SRS accessions contain multiple SRR runs; always resolve to SRR before calling `fasterq-dump`.
- Downloading directly with `fasterq-dump <SRR>` (without prefetch) works but uses more network retries and temp space.
