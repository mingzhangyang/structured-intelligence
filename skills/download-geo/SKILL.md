---
name: download-geo
description: Download supplementary data files, series matrices, and raw FASTQ links from NCBI GEO for a given GSE series or GSM sample accession.
---

# Skill: Download GEO

## Use When

- A user wants to download supplementary files (count matrices, CEL files, processed tables) for a GEO series (GSE) or sample (GSM).
- A user wants to download the series matrix file(s) for a GSE, which contain sample metadata and normalized expression values.
- A user wants to discover and fetch raw FASTQ files linked to a GEO series (which are stored in SRA and require `download-sra`).
- A user wants to bulk-download all supplementary files for a set of GSE accessions.
- A user wants to organize downloaded GEO files by sample or by file type.

## Inputs

- Required:
  - one or more GEO accessions: GSE (series) or GSM (sample)
- Optional:
  - `--type` — what to download: `supplementary` (default), `matrix`, `both`, or `sra-list`
  - `--outdir DIR` — output directory (default: `geo_downloads`)
  - `--filter PATTERN` — glob pattern to select supplementary files (e.g., `"*_counts.txt.gz"`, `"*.CEL.gz"`)
  - `--no-decompress` — keep files compressed (default: leave as-is, do not auto-decompress)
  - `--soft` — also download the full SOFT metadata file for the series
  - `--dry-run` — list files that would be downloaded without fetching them

## Workflow

1. Resolve the GEO FTP base path for the accession:
   - For `GSEnnnnn` where nnn is the numeric part:
     ```
     ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSEnnn/GSEnnnnn/
     ```
   - For `GSEnnnnnnn` (7-digit, prefix = `GSEnnnnnn`):
     ```
     ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSEnnnnnnn/GSEnnnnnnn/
     ```
   - Helper: `PREFIX="${ACC%???}nnn"` — replace last 3 digits with `nnn`.

2. List available files:
   ```bash
   curl -s "https://ftp.ncbi.nlm.nih.gov/geo/series/$PREFIX/$ACC/" 2>/dev/null
   # Or via NCBI GEO query API:
   curl -s "https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=$ACC&targ=self&form=text&view=brief"
   ```

3. Download supplementary files (if `--type supplementary` or `both`):
   ```bash
   wget -r -nH --cut-dirs=5 -np -nd \
     -P "$OUTDIR/$ACC/supplementary/" \
     "https://ftp.ncbi.nlm.nih.gov/geo/series/$PREFIX/$ACC/suppl/"
   ```
   Apply `--filter` pattern if provided.

4. Download series matrix (if `--type matrix` or `both`):
   ```bash
   wget -r -nH --cut-dirs=5 -np -nd \
     -P "$OUTDIR/$ACC/matrix/" \
     "https://ftp.ncbi.nlm.nih.gov/geo/series/$PREFIX/$ACC/matrix/"
   ```

5. Download SOFT file (if `--soft`):
   ```bash
   wget -P "$OUTDIR/$ACC/soft/" \
     "https://ftp.ncbi.nlm.nih.gov/geo/series/$PREFIX/$ACC/soft/"
   ```

6. Extract SRA run accessions for raw FASTQ (if `--type sra-list`):
   ```bash
   esearch -db gds -query "$ACC[Accession]" | elink -target sra | \
     efetch -format runinfo | awk -F',' 'NR>1 && $1!="" {print $1}'
   ```
   Write the SRR list to `$OUTDIR/$ACC/sra_accessions.txt` and instruct the user to run `download-sra` with this file.

7. Report: files downloaded, total size, destination paths. For `sra-list` mode, display the SRR list and the recommended `download-sra` command.

## Output Contract

- Supplementary files under `<outdir>/<GSE>/supplementary/`
- Series matrix files under `<outdir>/<GSE>/matrix/` (plain text, gzip-compressed)
- SOFT file under `<outdir>/<GSE>/soft/` (when `--soft` requested)
- `sra_accessions.txt` under `<outdir>/<GSE>/` (when `--type sra-list` requested, one SRR per line)
- `download_manifest.tsv` listing: `accession`, `file`, `size_bytes`, `url`, `local_path`
- Recommended `download-sra` command when raw FASTQ is needed

## Limits

- GEO FTP is accessible without authentication; no credentials are needed for public data.
- Supplementary files are whatever the submitter uploaded; format and content vary widely (CSV, TSV, CEL, H5AD, RDS, etc.).
- Series matrix files contain processed/normalized data, not raw counts. Raw counts, if available, are usually in supplementary files or in SRA.
- Raw sequencing data (FASTQ) is stored in SRA, not on the GEO FTP. Use `download-sra` with the `sra_accessions.txt` output of this skill to download raw reads.
- Some large GSE series have hundreds of supplementary files totalling many GB; always dry-run first to inspect file sizes.
- GEO does not provide MD5 checksums for supplementary files; integrity verification is not possible for supplementary downloads.
- Common failure cases:
  - FTP path resolution failure because the GSE numeric prefix is computed incorrectly; double-check the `nnn` suffix calculation
  - no supplementary files present (some series only have series matrix and SRA links)
  - wget following symlinks into unintended directories; use `--no-parent` flag
  - series matrix is split across multiple files (one per platform); all will be downloaded automatically
