---
name: search-ncbi-datasets
description: Search NCBI Datasets for genome assemblies, genes, taxonomy records, and virus genomes using the NCBI Datasets CLI or REST API.
---

# Skill: Search NCBI Datasets

## Use When

- A user wants to find and download genome assemblies from the NCBI Datasets portal.
- A user needs to query genomes by organism name, taxonomy ID, assembly accession (GCF/GCA), or assembly level (complete, chromosome, scaffold, contig).
- A user wants gene-level data: sequences, annotations, or orthologs by gene symbol, gene ID, or taxon.
- A user wants virus genome records (NCBI Virus) by species, collection date, host, or geographic region.
- A user wants summary statistics (assembly count, N50, total length) for a set of assemblies before downloading.
- A user wants to generate a dehydrated dataset package and rehydrate later, or get direct download links for genome FASTA/GFF/GTF files.

## Inputs

- Required:
  - one of: organism name or NCBI taxonomy ID, assembly accession (GCF_/GCA_), gene symbol or gene ID, or virus taxon
- Optional:
  - data type: `genome`, `gene`, `virus`, `taxonomy` (default: `genome`)
  - assembly level filter: `complete`, `chromosome`, `scaffold`, `contig`
  - assembly source filter: `refseq` (GCF) or `genbank` (GCA)
  - annotation filter: `annotated` (only assemblies with annotation)
  - reference-only flag: restrict to reference/representative genomes
  - include flags for genome downloads: `genome`, `rna`, `protein`, `cds`, `gff3`, `gtf`, `seq-report`
  - limit on number of results
  - output format: `json` (summary) or direct download (zip package)
  - output directory

## Workflow

1. Choose the interface:
   - **NCBI Datasets CLI** (`datasets` + `dataformat`): preferred for batch or scripted use.
   - **NCBI Datasets REST API**: use when the CLI is not installed.
     Base URL: `https://api.ncbi.nlm.nih.gov/datasets/v2/`

2. For genome assembly searches:
   - CLI: `datasets summary genome taxon "<organism>" --assembly-level complete --reference`
   - API: `GET https://api.ncbi.nlm.nih.gov/datasets/v2/genome/taxon/<taxon>/dataset_report`
   - Reformat summary with: `dataformat tsv genome --fields accession,organism-name,assembly-level,genome-size,contig-n50,annotation-info-release-date`

3. For gene searches:
   - CLI: `datasets summary gene symbol <GENE> --taxon "<organism>"`
   - CLI: `datasets summary gene id <gene_id>`

4. For virus genome searches:
   - CLI: `datasets summary virus genome taxon <taxon> --host "<host>" --geo-location "<country>"`
   - Filter by collection date range with `--released-after` / `--released-before`.

5. To download data:
   - `datasets download genome accession <GCF_> --include genome,gff3,gtf --filename <out>.zip`
   - For large batches, use `--dehydrated` and then `datasets rehydrate --directory <dir>`.

6. Parse the JSON summary to extract key fields and report a summary table.

## Output Contract

- Exact CLI command or API URL used
- Number of matching records
- Summary table for genome queries: Accession (GCF/GCA), Organism, Assembly Level, Genome Size (Mb), Contig N50, Annotation Date, Submitter
- Summary table for gene queries: Gene ID, Symbol, Full Name, Taxon, Location, RefSeq mRNA/Protein accessions
- Download command(s) for selected accessions
- Saved output files when a directory is provided:
  - `summary.json` (raw API/CLI output)
  - `summary.tsv` (reformatted with `dataformat`)
  - `accessions.txt` (one accession per line)

## Limits

- This skill depends on live access to `https://api.ncbi.nlm.nih.gov/datasets/v2/` or a local install of the `datasets` CLI.
- NCBI Datasets API rate limits apply; add `NCBI_API_KEY` environment variable or `--api-key` flag for higher throughput.
- The `datasets` CLI must be installed separately (available from https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/).
- Genome download packages can be very large; always check genome size and count before issuing a download.
- Not all assemblies in GenBank have annotation; use `--annotated` when annotation files are required.
- Virus genome data is stored separately from the main genome database; queries must use `datasets summary virus`.
- Common failure cases:
  - specifying a taxon name with incorrect spelling or outdated taxonomy
  - requesting `--include gff3` for assemblies without annotation (download will still proceed but GFF3 will be absent)
  - confusing GCF (RefSeq) with GCA (GenBank) accessions when a specific source is required
  - omitting `dataformat` to reformat JSON output, resulting in hard-to-parse raw JSON
