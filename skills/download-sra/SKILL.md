---
name: download-sra
description: Download raw sequencing data from NCBI SRA as FASTQ files using prefetch and fasterq-dump, with support for single accessions, batch lists, and BioProject expansion.
---

# Skill: Download SRA

## Use When

- A user wants to download FASTQ files from NCBI SRA given one or more SRR, SRX, SRS, or SRP accessions.
- A user has an accession list file and wants to batch-download all runs.
- A user wants to expand a BioProject (PRJNA) or SRA study (SRP) to its full run list and download all runs.
- A user wants paired-end reads split into R1 and R2 FASTQ files.
- A user wants to control output directory layout, thread count, or compression.
- A user wants to verify download integrity (MD5 / Vdb-validate) after prefetch.

## Inputs

- Required:
  - one of:
    - single SRR/SRX/SRS/SRP/PRJNA accession
    - path to a plain-text file of accessions (one per line)
- Optional:
  - `--outdir DIR` — output directory (default: `sra_downloads`)
  - `--threads N` — parallel threads for `fasterq-dump` (default: 6)
  - `--split-3` — split paired-end into R1/R2 plus unpaired (default; recommended)
  - `--split-files` — split into separate files per read (use when `--split-3` drops unpaired reads)
  - `--original-sra` — keep the `.sra` file after conversion (default: deleted)
  - `--skip-prefetch` — pipe directly through `fasterq-dump` without intermediate `.sra` (uses more temp disk)
  - `--gzip` — gzip-compress output FASTQ files (default: on)
  - `--min-spots N` — skip runs with fewer than N spots (default: 0, no filter)
  - `--max-size SIZE` — skip prefetch if expected size exceeds SIZE bytes
  - `--temp-dir DIR` — temp directory for fasterq-dump (default: system temp)
  - `--no-verify` — skip vdb-validate after prefetch

## Workflow

1. Resolve the input to a list of SRR accessions:
   - If the input is a file, read it line by line (skip blank lines and `#` comments).
   - If the input is a SRP/PRJNA/SRX/SRS accession, expand to SRR list:
     ```bash
     esearch -db sra -query "<accession>" | efetch -format runinfo | \
       awk -F',' 'NR>1 && $1!="" {print $1}'
     ```
   - If the input is an SRR, use it directly.
2. For each SRR in the list, run `scripts/run.sh`:
   - `prefetch --output-directory "$OUTDIR/sra_cache" "$SRR"` to download the `.sra` file.
   - Optionally run `vdb-validate "$OUTDIR/sra_cache/$SRR/$SRR.sra"` to verify integrity.
   - `fasterq-dump --split-3 --threads "$THREADS" --temp "$TMPDIR" --outdir "$OUTDIR/$SRR" "$OUTDIR/sra_cache/$SRR/$SRR.sra"`.
   - Gzip the resulting FASTQ files: `pigz -p "$THREADS"` or `gzip`.
   - Remove the `.sra` cache unless `--original-sra` was requested.
3. For batch mode (`scripts/batch_run.sh`), loop over the accession list sequentially or in parallel controlled by `--jobs N` (GNU parallel / xargs).
4. Print a per-run summary: SRR, spots downloaded, output files, size on disk, elapsed time.
5. Write `manifest.tsv` listing: SRR, sample name, R1 path, R2 path (if PE), size (bytes), md5sum.

## Output Contract

- Per-run output under `<outdir>/<SRR>/`:
  - `<SRR>_1.fastq.gz` and `<SRR>_2.fastq.gz` for paired-end (split-3)
  - `<SRR>.fastq.gz` for single-end
  - `<SRR>_unpaired.fastq.gz` for unpaired reads from split-3 (may be absent or empty)
- `manifest.tsv` in `<outdir>/` with columns: `run`, `sample`, `r1`, `r2`, `spots`, `size_bytes`, `md5_r1`, `md5_r2`
- Per-run log files under `<outdir>/logs/<SRR>.log`
- `accessions_failed.txt` listing SRRs that could not be downloaded

## Limits

- SRA Toolkit (`prefetch`, `fasterq-dump`, `vdb-validate`) must be installed and on `$PATH`.
- `fasterq-dump` requires substantial temp disk space (typically 6–10× the compressed FASTQ size); set `--temp-dir` to a partition with sufficient space.
- dbGaP controlled-access data requires a valid ngc token file; pass it as `NCBI_SRA_AUTH_TOKEN` or via `prefetch --ngc <token.ngc>`.
- Very large SRA runs (>500 GB) may time out on slow connections; consider using the SRA on AWS (`aws s3 cp s3://sra-pub-run-odp/sra/<SRR>/<SRR>`) as an alternative.
- `--split-3` is the recommended default for paired-end data; some older SRA entries do not store paired information and will produce single-end output regardless.
- Common failure cases:
  - insufficient temp disk causing `fasterq-dump` to abort mid-run, leaving partial FASTQ files
  - rate-limiting or network timeout during `prefetch` on large runs; retry with exponential backoff
  - accession does not exist or has been suppressed by submitter
  - mixing SRX/SRS into `fasterq-dump` directly without first resolving to SRR accessions
