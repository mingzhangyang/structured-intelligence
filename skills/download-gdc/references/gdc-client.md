# GDC Data Transfer Tool Reference

## Overview

`gdc-client` is the official NCI tool for downloading files from the Genomic Data Commons. It handles parallel downloads, retries, and MD5 verification automatically.

## Installation

```bash
# Download from GDC
wget https://gdc.cancer.gov/files/public/file/gdc-client_<version>_Ubuntu_x64.zip
unzip gdc-client_*.zip
chmod +x gdc-client
sudo mv gdc-client /usr/local/bin/
```

## Core Download Command

```bash
gdc-client download \
    -m manifest.txt \          # GDC manifest TSV
    [-t token.txt] \           # user token (controlled access only)
    -d ./output_dir \          # output directory
    --n-processes 4 \          # parallel streams
    --retry-amount 3           # retries per file
```

## Manifest Format

GDC manifests are TSV files with these columns:

| Column | Description |
|--------|-------------|
| `id` | File UUID |
| `filename` | Output filename |
| `md5` | Expected MD5 checksum |
| `size` | File size in bytes |
| `state` | `live` (downloadable) or other states |

Only `state=live` files can be downloaded. Filter the manifest to remove non-live entries.

## GDC REST API

### Build a manifest programmatically

```bash
# Open-access files for a project + data type
curl -XPOST "https://api.gdc.cancer.gov/files" \
  -H "Content-Type: application/json" \
  -d '{
    "filters": {
      "op": "and",
      "content": [
        {"op": "=", "content": {"field": "cases.project.project_id", "value": "TCGA-BRCA"}},
        {"op": "=", "content": {"field": "data_type", "value": "Gene Expression Quantification"}},
        {"op": "=", "content": {"field": "access", "value": "open"}}
      ]
    },
    "fields": "file_id,file_name,md5sum,file_size,state,access",
    "size": "10000",
    "format": "tsv"
  }'
```

### Download manifest by UUID list

```bash
curl -o manifest.txt \
  "https://api.gdc.cancer.gov/manifest?ids=uuid1,uuid2,uuid3"
```

### Download a single file directly (open-access)

```bash
curl -o output.file \
  "https://api.gdc.cancer.gov/data/<uuid>"
```

## Access Tiers

| Access | Token Required | Examples |
|--------|---------------|---------|
| `open` | No | Gene expression counts, masked somatic mutations, methylation beta values |
| `controlled` | Yes (dbGaP) | Raw BAM files, germline VCF, original sequencing data |

## Token Management

- Tokens are obtained from https://portal.gdc.cancer.gov → Profile → Download Token
- Tokens expire after **30 days**; regenerate before each download session
- Store tokens in a file (not in environment variables) to avoid shell history logging
- Controlled-access data requires dbGaP authorization (separate from GDC account)

## Key GDC Field Names for Filtering

| Field | Example Values |
|-------|---------------|
| `cases.project.project_id` | `TCGA-BRCA`, `TARGET-ALL-P2` |
| `data_type` | `Aligned Reads`, `Gene Expression Quantification`, `Masked Somatic Mutation` |
| `data_category` | `Sequencing Reads`, `Transcriptome Profiling`, `Simple Nucleotide Variation` |
| `experimental_strategy` | `RNA-Seq`, `WXS`, `WGS`, `ChIP-Seq` |
| `workflow_type` | `STAR 2-Pass`, `MuTect2`, `HTSeq - Counts` |
| `access` | `open`, `controlled` |

## File Organization

Downloaded files are placed under `<outdir>/<uuid>/<filename>`. To flatten:

```bash
find ./gdc_downloads -name "*.bam" -exec mv {} ./bam_files/ \;
```

## Common Gotchas

- A manifest may mix open and controlled files; gdc-client will fail on controlled files without a token.
- Token expiry mid-download does not resume gracefully; check token validity before starting large jobs.
- TCGA whole-genome BAMs are 50–200 GB each; estimate total size from `size` column in manifest before downloading.
- GDC file UUIDs are stable, but a file may be superseded by a newer version; check `state` field.
- `--n-processes > 8` rarely improves throughput and may trigger rate limiting.
