---
name: download-gdc
description: Download files from the NCI Genomic Data Commons (GDC) using the GDC Data Transfer Tool and REST API, supporting both open-access and controlled-access data.
---

# Skill: Download GDC

## Use When

- A user wants to download BAM, VCF, FASTQ, or other files from the NCI GDC (TCGA, TARGET, CPTAC, etc.).
- A user has a GDC manifest file and wants to download all listed files.
- A user wants to query the GDC API to build a manifest by project, data type, workflow, or data category.
- A user wants to download controlled-access data using a GDC user token.
- A user wants to verify downloaded file integrity using MD5 checksums from the GDC manifest.
- A user wants to organize downloaded files by case, sample, or data type.

## Inputs

- Required:
  - one of:
    - path to a GDC manifest file (TSV with columns: `id`, `filename`, `md5`, `size`, `state`)
    - GDC file UUID(s) to generate a manifest on the fly
    - GDC project ID (e.g., `TCGA-BRCA`) and filters to query and build a manifest
- Optional:
  - `--token-file FILE` — GDC user token for controlled-access data (required for dbGaP-protected files)
  - `--outdir DIR` — output directory (default: `gdc_downloads`)
  - `--jobs N` — number of parallel download streams (default: 1; max recommended: 8)
  - `--retries N` — retry count on network errors (default: 3)
  - `--no-verify` — skip MD5 verification after download
  - `--dry-run` — print manifest and download commands without executing
  - `--data-type TYPE` — filter for manifest generation (e.g., `"Aligned Reads"`, `"Masked Somatic Mutation"`)
  - `--workflow TYPE` — workflow filter (e.g., `"STAR 2-Pass"`, `"MuTect2"`)
  - `--experimental-strategy` — filter (e.g., `"RNA-Seq"`, `"WXS"`, `"WGS"`)

## Workflow

1. **Obtain a manifest**:
   - If a manifest file is provided, validate it (check columns: `id`, `filename`, `md5`, `size`, `state`).
   - If UUIDs are provided, generate a manifest via GDC API:
     ```bash
     curl -o manifest.txt \
       "https://api.gdc.cancer.gov/manifest?ids=$(echo "$UUIDS" | tr ' ' ',')"
     ```
   - If a project ID and filters are provided, query the GDC files endpoint and produce a manifest:
     ```bash
     curl -XPOST "https://api.gdc.cancer.gov/files" \
       -H "Content-Type: application/json" \
       -d '{"filters":{"op":"and","content":[
             {"op":"=","content":{"field":"cases.project.project_id","value":"TCGA-BRCA"}},
             {"op":"=","content":{"field":"data_type","value":"Aligned Reads"}},
             {"op":"=","content":{"field":"access","value":"open"}}]},
            "fields":"file_id,file_name,md5sum,file_size,state",
            "size":"10000","format":"tsv"}'
     ```

2. **Check access tier**: inspect the `access` field in the API response.
   - `open`: no token needed.
   - `controlled`: `--token-file` is required; warn the user if it is absent.

3. **Download with gdc-client**:
   ```bash
   gdc-client download \
     -m manifest.txt \
     [-t token.txt] \
     -d "$OUTDIR" \
     --n-processes "$JOBS" \
     --retry-amount "$RETRIES"
   ```

4. **Verify MD5 checksums**:
   ```bash
   while IFS=$'\t' read -r uuid filename md5 size state; do
     [[ "$uuid" == "id" ]] && continue
     actual=$(md5sum "$OUTDIR/$uuid/$filename" | awk '{print $1}')
     if [[ "$actual" != "$md5" ]]; then
       echo "CHECKSUM FAIL: $filename" >&2
     fi
   done < manifest.txt
   ```

5. **Organize files** (optional): flatten the `<uuid>/<filename>` layout into a user-specified directory structure by data type, project, or sample.

6. Write `download_report.tsv` with: `uuid`, `filename`, `expected_md5`, `actual_md5`, `size_bytes`, `status`.

## Output Contract

- Downloaded files under `<outdir>/<uuid>/<filename>` (GDC default layout)
- `manifest.txt` used for the download (generated or provided)
- `download_report.tsv` with columns: `uuid`, `filename`, `expected_md5`, `actual_md5`, `size_bytes`, `status` (`OK` / `CHECKSUM_FAIL` / `MISSING`)
- `failed_uuids.txt` listing UUIDs that failed all retry attempts
- Exact `gdc-client` command issued

## Limits

- GDC Data Transfer Tool (`gdc-client`) must be installed; download from https://gdc.cancer.gov/access-data/gdc-data-transfer-tool.
- Controlled-access data requires a GDC user token obtained from https://portal.gdc.cancer.gov after dbGaP authorization. Tokens expire after 30 days.
- Open-access files (e.g., gene expression counts, masked somatic mutations) do not require a token.
- GDC manifest files are project-snapshot–specific; file UUIDs are stable but a manifest generated today may differ from one generated later as projects update.
- Parallel downloads (`--jobs > 1`) may trigger GDC rate limiting; start with 3–4 jobs and increase cautiously.
- Common failure cases:
  - expired or invalid token causing 403 errors on controlled-access files
  - manifest containing files from multiple access tiers; download will fail on controlled-access files if no token is provided
  - disk space exhaustion for large TCGA BAM files (whole-genome BAMs are 50–200 GB each)
  - MD5 mismatch indicating a partial or corrupted download; delete the file and retry
  - mixing GDC file UUIDs with TCGA barcode IDs (barcodes must be resolved to UUIDs via the GDC API before use)
