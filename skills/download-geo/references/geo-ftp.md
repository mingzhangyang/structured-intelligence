# GEO FTP Reference

## Overview

NCBI GEO data is hosted on a public FTP server at `ftp.ncbi.nlm.nih.gov/geo/`. All files are accessible without authentication via both FTP and HTTPS.

## Directory Structure

```
ftp.ncbi.nlm.nih.gov/geo/
├── series/
│   └── GSEnnn/          ← prefix (last 3 digits replaced by "nnn")
│       └── GSEnnnnnn/   ← exact accession
│           ├── suppl/   ← supplementary files
│           ├── matrix/  ← series matrix file(s)
│           └── soft/    ← SOFT metadata file
├── samples/
│   └── GSMnnn/
│       └── GSMnnnnnn/
│           └── suppl/
└── platforms/
    └── GPLnnn/
        └── GPLnnnnnn/
```

## FTP Path Calculation

| Accession | Prefix | Example |
|-----------|--------|---------|
| GSE1–GSE999 | `GSEnnn` | `GSEnnn/GSE123/` |
| GSE1000–GSE9999 | `GSE1nnn` | `GSE1nnn/GSE1234/` |
| GSE10000–GSE99999 | `GSE10nnn` | `GSE10nnn/GSE10234/` |
| GSE100000–GSE999999 | `GSE100nnn` | `GSE100nnn/GSE100234/` |

**Rule**: replace the last 3 digits with `nnn`.

```bash
ACC="GSE12345"
NUMERIC="${ACC#GSE}"                                # 12345
PREFIX="GSE${NUMERIC:0:$(( ${#NUMERIC} - 3 ))}nnn" # GSE12nnn
URL="https://ftp.ncbi.nlm.nih.gov/geo/series/${PREFIX}/${ACC}/"
```

## File Types

### Supplementary Files (`suppl/`)

Whatever the submitter deposited. Common formats:

| Extension | Content |
|-----------|---------|
| `*_counts.txt.gz` | Raw count matrix (RNA-seq) |
| `*_fpkm.txt.gz` / `*_tpm.txt.gz` | Normalized expression |
| `*.CEL.gz` | Affymetrix microarray raw intensity |
| `*.idat.gz` | Illumina methylation array |
| `*_processed.txt.gz` | Submitter-processed data |
| `*.h5ad.gz` / `*.h5` | Single-cell AnnData or HDF5 |
| `*.rds` | R data object |
| `RAW.tar` | Archive of per-sample files |

### Series Matrix (`matrix/`)

A plain-text file containing:
- `!Series_*` lines: series-level metadata
- `!Sample_*` lines: per-sample metadata including `!Sample_characteristics_ch1`
- `!series_matrix_table_begin` / `!series_matrix_table_end` block: normalized expression matrix (probes × samples)

Multi-platform series have one matrix file per platform.

### SOFT File (`soft/`)

Full structured metadata in GEO SOFT format. Larger than the matrix file but contains all entity relationships (series → samples → platforms).

## Download Commands

```bash
# Download all supplementary files
wget -r -nH --cut-dirs=99 -np -nd \
    -P ./suppl/ \
    "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE12nnn/GSE12345/suppl/"

# Download only count matrices
wget -r -nH --cut-dirs=99 -np -nd \
    --accept="*_counts*" \
    -P ./suppl/ \
    "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE12nnn/GSE12345/suppl/"

# Download series matrix
wget -r -nH --cut-dirs=99 -np -nd \
    -P ./matrix/ \
    "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE12nnn/GSE12345/matrix/"
```

## Getting Raw FASTQ

GEO does not store raw FASTQ directly. They are in SRA and linked via a GSE's SRA run table.

```bash
# Get SRR accessions for a GSE
esearch -db gds -query "GSE12345[Accession]" | elink -target sra | \
    efetch -format runinfo | awk -F',' 'NR>1 && $1~/^[SE]RR/ {print $1}'
```

Then use `download-sra` with the resulting SRR list.

## GEO Query API

```bash
# Get series metadata in text format
curl "https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE12345&targ=self&form=text&view=brief"

# Get all sample accessions for a series
curl "https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE12345&targ=gsm&form=text&view=brief"
```

## Common Gotchas

- `RAW.tar` in the supplementary directory contains per-sample files; extract with `tar -xf RAW.tar`.
- Series matrices are gzip-compressed (`.txt.gz`); decompress before parsing with R or Python.
- Some GEO series are very large (>1000 samples); the supplementary directory may be tens of GB.
- Not every GSE has supplementary files; check the directory listing before downloading.
- wget `--cut-dirs=99` combined with `-nd` flattens the directory; adjust if you need to preserve paths.
