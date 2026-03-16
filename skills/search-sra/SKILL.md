---
name: search-sra
description: Search NCBI Sequence Read Archive (SRA) for sequencing runs, experiments, studies, and samples using E-utilities or the NCBI Datasets CLI.
---

# Skill: Search SRA

## Use When

- A user wants to find sequencing runs, experiments, studies, or biosamples in the NCBI Sequence Read Archive.
- A user needs to look up SRA accessions (SRR, SRX, SRS, SRP, SAMN) or search by organism, tissue, assay type, or keyword.
- A user wants to retrieve run metadata (file size, read count, platform, library strategy) before downloading.
- A user wants to list all runs belonging to a BioProject or BioSample.
- A user needs to build a manifest of SRR accessions for downstream download with `prefetch` or `fasterq-dump`.
- A user wants to filter SRA by sequencing platform (Illumina, PacBio, Nanopore) or library layout (PAIRED, SINGLE).

## Inputs

- Required:
  - one of: free-text search query, SRA/BioProject/BioSample accession, organism name, or NCBI taxonomy ID
- Optional:
  - target SRA entity type: `run`, `experiment`, `sample`, `study` (default: `run`)
  - organism filter (e.g., `"Homo sapiens"`, `"Mus musculus"`)
  - library strategy filter (e.g., `RNA-Seq`, `WGS`, `ChIP-Seq`, `ATAC-seq`)
  - platform filter (e.g., `ILLUMINA`, `PACBIO_SMRT`, `OXFORD_NANOPORE`)
  - library layout: `PAIRED` or `SINGLE`
  - date range: `mindate` / `maxdate` in `YYYY/MM/DD`
  - maximum results to return (`retmax`, default 20)
  - output format: `json`, `xml`, or `runinfo` CSV
  - output directory

## Workflow

1. Determine the search strategy:
   - If given a bare accession (SRR/SRX/SRS/SRP/PRJNA/SAMN), map it to the correct NCBI database:
     - `SRR`, `SRX`, `SRS`, `SRP` → `sra`
     - `PRJNA` → `bioproject`, then link to `sra`
     - `SAMN` → `biosample`, then link to `sra`
   - If given a free-text query, use `esearch -db sra` with structured field tags when helpful:
     - organism: `[Organism]`
     - library strategy: `[Strategy]`
     - platform: `[Platform]`
     - layout: `[Layout]`
2. Run `esearch -db sra -query "<term>"` to retrieve UIDs.
3. Pipe to `esummary -db sra -format json` or `efetch -db sra -format runinfo` for metadata.
4. For BioProject-level queries, use `esearch -db bioproject | elink -target sra | efetch -format runinfo` to get the full run table.
5. Parse the run info CSV or JSON to extract: `Run`, `SampleName`, `BioSample`, `Experiment`, `LibraryStrategy`, `LibraryLayout`, `Platform`, `spots`, `bases`, `size_MB`, `PublishDate`.
6. Report a summary table of matching runs and key metadata.
7. If the user wants to download, provide the `prefetch` or `fasterq-dump` command with the accession list.

## Output Contract

- Search query used (exact E-utilities command)
- Number of hits found
- Summary table with columns: Run (SRR), Sample, BioProject, Strategy, Platform, Layout, Spots, Bases, Size (MB), Date
- Full accession list suitable for use with `prefetch` or `fasterq-dump`
- Saved output files when an output directory is provided:
  - `esearch.json`
  - `runinfo.csv` (when `efetch -format runinfo` is used)
  - `accessions.txt` (one SRR per line)

## Limits

- This skill depends on live access to `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/`.
- NCBI rate limit: 3 requests/second without API key, 10/second with API key. Always pass `--email` for repeated queries.
- `esummary` JSON field names for SRA differ from the `runinfo` CSV columns; prefer `efetch -format runinfo` for tabular metadata.
- Private or access-controlled SRA datasets (dbGaP) cannot be retrieved without an authorized token.
- Very large BioProjects (>10 000 runs) require paging with `WebEnv` + `query_key`.
- Common failure cases:
  - confusing SRA database UIDs with run accessions (they are not the same)
  - querying `bioproject` instead of `sra` when an SRR is needed
  - omitting `[Organism]` field tag, causing organism name to match free text in other fields
  - requesting `retmax` > 10 000 without using history server
