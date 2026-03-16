---
name: search-ena
description: Search the EMBL-EBI European Nucleotide Archive (ENA) for sequencing studies, runs, samples, and experiments using the ENA Portal REST API.
---

# Skill: Search ENA

## Use When

- A user wants to find sequencing data in the European Nucleotide Archive (ENA) hosted at ebi.ac.uk.
- A user needs to look up ENA/SRA accessions: PRJEB/PRJNA (study), ERS/SRS (sample), ERX/SRX (experiment), ERR/SRR (run).
- A user wants to query ENA by organism, tissue, assay type, instrument, library strategy, or free-text keyword.
- A user wants structured metadata (TSV/JSON) for runs or samples in a study without installing any software.
- A user needs FASTQ or BAM download URLs (FTP or HTTPS) for ENA runs.
- A user wants to find public datasets equivalent to those in NCBI SRA (ENA mirrors most SRA submissions).

## Inputs

- Required:
  - one of: ENA/SRA accession (PRJEB/PRJNA/ERR/SRR/ERS/SRS/ERX/SRX), free-text search query, or taxonomy ID
- Optional:
  - result type (ENA entity): `study`, `sample`, `experiment`, `run`, `analysis` (default: `run`)
  - organism filter (scientific name or NCBI taxonomy ID)
  - library strategy filter (e.g., `RNA-Seq`, `WGS`, `AMPLICON`, `ChIP-Seq`)
  - instrument platform filter (e.g., `ILLUMINA`, `OXFORD_NANOPORE`, `PACBIO_SMRT`)
  - library layout: `PAIRED` or `SINGLE`
  - fields to return (comma-separated ENA field names, or `all` for full metadata)
  - date range: `first_public` range in `YYYY-MM-DD`
  - maximum results (`limit`, default 100)
  - output format: `tsv` or `json`
  - output file path

## Workflow

1. Construct an ENA Portal API search request:
   ```
   GET https://www.ebi.ac.uk/ena/portal/api/search
     ?result=<result-type>
     &query=<lucene-query>
     &fields=<field-list>
     &format=<tsv|json>
     &limit=<n>
   ```
   - For accession-based lookup: `query=study_accession="<PRJEB>"` or `query=run_accession="<ERR>"`
   - For text search: `query=<term>` with optional field qualifiers such as `scientific_name="Homo sapiens"`
   - For taxonomy: `query=tax_eq(<taxon_id>)` or `query=tax_tree(<taxon_id>)` (includes descendants)

2. Recommended field sets by result type:
   - `run`: `run_accession,experiment_accession,sample_accession,study_accession,scientific_name,instrument_platform,library_strategy,library_layout,read_count,base_count,fastq_ftp,fastq_bytes,first_public`
   - `study`: `study_accession,secondary_study_accession,study_title,tax_id,scientific_name,study_description,first_public`
   - `sample`: `sample_accession,secondary_sample_accession,scientific_name,tax_id,sample_title,collection_date,country,tissue_type`

3. Parse the response to build a summary table.
4. Extract `fastq_ftp` or `fastq_aspera` columns for direct download links.
5. For large queries (>1000 runs), use `limit` and `offset` for paging, or stream with `format=tsv`.
6. Report download commands using `wget` or `curl` for the FTP URLs.

## Output Contract

- API request URL used
- Number of matching records
- Summary table with key fields per result type (accession, organism, strategy, platform, read count, size, date)
- FASTQ download URLs (FTP and HTTPS) for run-level queries
- Saved output files when a path is provided:
  - `results.tsv` or `results.json`
  - `fastq_urls.txt` (one URL per line, ready for `wget -i` or `aria2c -i`)

## Limits

- This skill depends on live access to `https://www.ebi.ac.uk/ena/portal/api/`.
- ENA Portal API returns at most 100 000 rows per request; use paging for larger result sets.
- Not all SRA submissions are mirrored in ENA immediately; newly submitted data may not be available yet.
- Controlled-access datasets (e.g., from EGA) are not accessible through the ENA Portal API.
- The `fastq_ftp` field may be empty for runs that are only available as SRA format; in that case fall back to `sra_ftp` or use `fasterq-dump`.
- ENA Lucene query syntax differs from NCBI E-utilities query syntax; do not mix them.
- Common failure cases:
  - using NCBI-style `[field]` tag syntax instead of ENA `field="value"` syntax
  - requesting `result=run` but filtering by study-level fields not propagated to run records
  - `fastq_ftp` returning multiple semicolon-separated URLs (for paired-end runs); must split on `;`
  - omitting `tax_tree()` and only getting exact taxon matches, missing subspecies/strains
