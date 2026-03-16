---
name: search-geo
description: Search NCBI Gene Expression Omnibus (GEO) for expression datasets, series, samples, and platforms using E-utilities or the GEO query API.
---

# Skill: Search GEO

## Use When

- A user wants to find expression datasets, RNA-seq series, microarray experiments, or epigenomics datasets in NCBI GEO.
- A user needs to look up GEO accessions: GSE (series), GSM (sample), GPL (platform), or GDS (curated dataset).
- A user wants to search GEO by organism, tissue, disease, treatment, assay type, or free-text keyword.
- A user wants to retrieve series metadata: number of samples, associated publication (PMID), submission date, platform.
- A user wants a list of GSM sample accessions for a given GSE series.
- A user wants to find GEO datasets suitable for a specific analysis (e.g., bulk RNA-seq of a specific cell type).

## Inputs

- Required:
  - one of: free-text search query, GEO accession (GSE/GSM/GPL/GDS), organism name, or PubMed ID
- Optional:
  - GEO entity type: `series` (GSE), `sample` (GSM), `platform` (GPL), or `dataset` (GDS)
  - organism filter (e.g., `"Homo sapiens"[Organism]`)
  - experiment type filter (e.g., `"Expression profiling by high throughput sequencing"[DataSet Type]`)
  - date range: `mindate` / `maxdate` in `YYYY/MM/DD`
  - maximum results (`retmax`, default 20)
  - output format: `json`, `xml`, or `soft`
  - output directory

## Workflow

1. Determine the NCBI database:
   - `GSE`, `GSM`, `GPL` → `geo` (use `esearch -db geo`)
   - `GDS` → `gds` (use `esearch -db gds`)
   - For most keyword searches, use `gds` which indexes curated datasets and series.
2. Build the query string with field tags when helpful:
   - organism: `"Homo sapiens"[Organism]`
   - data type: `"Expression profiling by high throughput sequencing"[DataSet Type]`
   - platform: `GPL570[Platform]`
   - publication: `<PMID>[PubMed ID]`
3. Run `esearch -db gds -query "<term>" | esummary -format json` to retrieve series metadata.
4. For a known GSE accession, fetch metadata via the GEO accession API:
   ```
   https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=<GSE>&targ=self&form=text&view=brief
   ```
5. To enumerate all samples in a series:
   - `esearch -db gds -query "GSE12345[Accession]" | elink -target geosamples | esummary`
   - Or fetch the series matrix from `ftp://ftp.ncbi.nlm.nih.gov/geo/series/`
6. Parse metadata to extract: accession, title, organism, type, sample count, platform, publication PMID, submission date, supplementary file URLs.
7. Report a summary table and, if requested, supplementary download links.

## Output Contract

- Search query used (exact E-utilities command or API URL)
- Number of hits found
- Summary table with columns: Accession (GSE), Title, Organism, Type, Samples (#), Platform, PMID, Date
- List of GSM sample accessions for a queried series
- FTP/HTTPS links to raw data (supplementary files, series matrix) when available
- Saved output files when an output directory is provided:
  - `esearch.json`
  - `esummary.json`
  - `samples.txt` (one GSM per line, for series-level queries)

## Limits

- This skill depends on live access to `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/` and `https://www.ncbi.nlm.nih.gov/geo/`.
- NCBI rate limit: 3 requests/second without API key, 10/second with API key.
- GEO `gds` database indexes curated GEO DataSets; not every GSE series becomes a GDS entry.
- Supplementary raw data may be large; this skill returns metadata and links, not the data itself.
- Controlled-access GEO datasets (e.g., human genotype data) require dbGaP authorization.
- The `SOFT` format is the canonical GEO text format; XML and JSON are available via E-utilities summary.
- Common failure cases:
  - querying the `geo` database instead of `gds` for series-level searches (use `gds` for keyword search)
  - confusing GSE (series) with GDS (curated dataset) — not all GSEs have a GDS entry
  - expecting `retmode=json` for `efetch` on GEO (only `SOFT` and XML are supported by `efetch`)
  - missing sample-level detail because only the series summary was fetched
