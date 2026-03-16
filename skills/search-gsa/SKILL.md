---
name: search-gsa
description: Search CNCB Genome Sequence Archive (GSA) for sequencing runs, experiments, studies, and samples deposited at the China National Center for Bioinformation.
---

# Skill: Search GSA

## Use When

- A user wants to find sequencing data deposited in the CNCB Genome Sequence Archive (GSA) at ngdc.cncb.ac.cn.
- A user needs to look up GSA accessions: CRA (project), CRX (experiment), CRR (run), CRS (sample), or SAMC (biosample).
- A user wants to retrieve run-level metadata (read count, file size, platform, library strategy) for data in GSA.
- A user wants to search GSA by organism, tissue, disease, keyword, or data type.
- A user wants to list all runs belonging to a GSA project (CRA accession).
- A user needs the download URL or FASP path for CRR files from CNCB.

## Inputs

- Required:
  - one of: free-text search query, GSA accession (CRA/CRX/CRR/CRS/SAMC), organism name, or NCBI taxonomy ID
- Optional:
  - data type filter: `Genome`, `Transcriptome`, `Metagenome`, `Epigenome`, `Variation`, `Proteome`
  - library strategy filter (e.g., `RNA-Seq`, `WGS`, `ChIP-Seq`, `ATAC-Seq`)
  - sequencing platform (e.g., `Illumina`, `PacBio`, `ONT`)
  - organism filter (scientific name or taxonomy ID)
  - output format: `json` or `tsv`
  - maximum results (`size`, default 20)
  - output directory

## Workflow

1. Determine the access method:
   - **Direct accession lookup**: construct the CNCB accession detail URL:
     - `https://ngdc.cncb.ac.cn/gsa/browse/<CRA-accession>` for projects
     - `https://ngdc.cncb.ac.cn/gsa/run/<CRR-accession>` for individual runs
   - **Keyword search**: use the GSA search API endpoint:
     ```
     GET https://ngdc.cncb.ac.cn/gsa/search?searchTerm=<query>&page=1&pageSize=20
     ```
   - **Programmatic metadata fetch**: use the GSA data API:
     ```
     GET https://ngdc.cncb.ac.cn/gsa/api/v1/project/<CRA>
     GET https://ngdc.cncb.ac.cn/gsa/api/v1/run/<CRR>
     ```
2. Parse the response to extract: accession, title, organism, submission date, run count, total bases, platform, and library strategy.
3. For project-level queries, enumerate all CRR runs and collect per-run metadata.
4. Construct download URLs for CRR files:
   - FTP: `ftp://download.cncb.ac.cn/gsa/<CRA>/<CRX>/<CRR>/`
   - HTTPS: `https://download.cncb.ac.cn/gsa/<CRA>/<CRX>/<CRR>/`
5. Report a summary table and the accession list.

## Output Contract

- Search or fetch request URL used
- Number of matching projects or runs
- Summary table with columns: Accession (CRR/CRA), Title, Organism, Platform, Strategy, Spots, Bases, Size, Submission Date
- Download URL(s) for CRR files
- Accession list saved to `accessions.txt` when an output directory is provided
- Optional `metadata.json` or `metadata.tsv` with full per-run fields

## Limits

- GSA web API is subject to change; confirm endpoint availability with a test request if needed.
- Some datasets in GSA are access-controlled and require registration at ngdc.cncb.ac.cn before download.
- GSA accessions follow CNCB conventions (CRA/CRX/CRR/CRS) distinct from NCBI (SRP/SRX/SRR/SRS); do not mix them.
- CNSA (China National Sequence Archive, for assembled genomes) is a separate archive also at CNCB; GSA is specifically for raw sequencing data.
- The FTP server may be slow for users outside mainland China; HTTPS is generally preferred.
- Common failure cases:
  - confusing CRA (project) with CRR (run) accession types
  - attempting to use NCBI E-utilities with GSA accessions (they are not indexed by NCBI)
  - missing authentication cookie when accessing controlled-access datasets
  - constructing download paths without the correct CRA/CRX/CRR hierarchy
