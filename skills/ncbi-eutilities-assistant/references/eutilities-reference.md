# NCBI E-utilities Reference

This skill is based on NCBI's official Entrez Programming Utilities documentation:

- General introduction and usage policy:
  - https://www.ncbi.nlm.nih.gov/books/NBK25497/
- Parameter and endpoint details:
  - https://www.ncbi.nlm.nih.gov/books/NBK25499/
- Entrez Programming Utilities Help landing page:
  - https://www.ncbi.nlm.nih.gov/books/NBK25501/

## Core Endpoints

The bundled wrapper script focuses on the six endpoints that cover most retrieval workflows:

1. `einfo`
   - discover database names and database-specific metadata
   - useful when you need to inspect fields, links, or update timestamps

2. `esearch`
   - search a database by query term
   - can return UIDs directly or store the result set in the Entrez History server with `usehistory=y`

3. `esummary`
   - retrieve document summaries for IDs or a history result set

4. `efetch`
   - retrieve full records in database-specific formats
   - format support depends on `db`, `retmode`, and `rettype`

5. `elink`
   - move from one Entrez database to related records in another database
   - can also generate a history set for follow-on retrieval

6. `epost`
   - upload a list of UIDs to the Entrez History server
   - useful when IDs already exist locally and later steps should operate in batches

## Usage Policy

NCBI's official guidance says:

- stay at or below 3 requests per second without an API key
- with an API key, the default supported rate is 10 requests per second
- for large jobs, prefer weekends or off-peak hours
- include `tool` and `email` in requests; include `api_key` when needed

## Recommended Patterns

### Inspect a database

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh info --db pubmed --retmode json
```

### Search and keep history for later retrieval

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh search \
  --db pubmed \
  --term 'CRISPR base editing[Title/Abstract]' \
  --retmax 20 \
  --usehistory y \
  --retmode json
```

### Summarize a specific set of IDs

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh summary \
  --db pubmed \
  --id 39696283,39650267 \
  --retmode json
```

### Fetch records from history

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh fetch \
  --db pubmed \
  --webenv '<WebEnv>' \
  --query-key 1 \
  --retmode xml \
  --retmax 100
```

### Upload IDs and continue with batch retrieval

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh post \
  --db protein \
  --id-file ./protein_ids.txt
```

### Run a higher-level PubMed workflow

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh pubmed-workflow \
  --term 'CRISPR base editing[Title/Abstract]' \
  --retmax 20 \
  --include-fetch yes \
  --fetch-retmode xml \
  --fetch-rettype abstract \
  --out-dir ./pubmed-run
```

This workflow does:

1. `esearch` against `pubmed` with `usehistory=y`
2. `esummary` against the returned history set
3. optional `efetch` for PubMed records
4. writes a `manifest.json` with counts, IDs, `WebEnv`, `query_key`, and output paths

### Run a PubMed literature-review extraction workflow

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh pubmed-review \
  --term 'large language model systematic review[Title/Abstract]' \
  --retmax 25 \
  --reldate 365 \
  --out-dir ./pubmed-review
```

This workflow does:

1. `esearch` against `pubmed` with `usehistory=y`
2. `esummary` for the selected batch
3. `efetch` in PubMed XML abstract form
4. parses the XML into `records.json` and `records.jsonl`

Each extracted record includes fields intended for downstream review work, such as:

- `pmid`
- `title`
- `abstract`
- `abstract_sections`
- `journal`
- `publication_year`
- `authors`
- `publication_types`
- `mesh_terms`
- `keywords`
- `article_ids`

### Run a recent-progress PubMed update brief

```bash
./skills/ncbi-eutilities-assistant/scripts/run.sh pubmed-update-brief \
  --term 'CRISPR' \
  --reldate 7 \
  --retmax 20 \
  --out-dir ./crispr-weekly-brief
```

This workflow does:

1. `esearch` against `pubmed` over a recent time window
2. `esummary` and `efetch` for the retrieved batch
3. extracts structured records into JSON and JSONL
4. writes a deterministic `brief.md` summarizing notable papers, repeated themes, and a watchlist

For a monthly brief, change `--reldate 7` to `--reldate 30`.

## Parameter Notes

- `db` names are Entrez database identifiers such as `pubmed`, `gene`, `protein`, `nuccore`, `assembly`, and `snp`.
- `tool` should identify the calling software and should not contain internal spaces.
- `email` should be a valid contact address for the software developer or operator.
- `api_key` increases the supported request rate.
- `WebEnv` and `query_key` are the key handles for History server workflows.
- For large ID lists, `POST` is preferred. The wrapper script auto-selects `POST` for ID files and large ID batches.

## Practical Caveats

- `EFetch` is the most database-specific endpoint; not every `retmode` / `rettype` pair is valid.
- `retmode=json` is useful where supported, but XML remains the common denominator across E-utilities.
- A successful `esearch` response can still produce zero IDs; the downstream command should check result counts instead of assuming success implies hits.
