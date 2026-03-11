---
name: ncbi-eutilities-assistant
description: Query NCBI Entrez databases through official E-utilities with deterministic search, summary, fetch, link, and history workflows.
---

# Skill: NCBI E-utilities Assistant

## Use When

- A user wants to query NCBI Entrez databases such as `pubmed`, `gene`, `protein`, `nuccore`, `assembly`, or `snp` through the official E-utilities API.
- A user needs deterministic command-line access to `einfo`, `esearch`, `esummary`, `efetch`, `elink`, or `epost`.
- A user wants a higher-level PubMed workflow that searches, summarizes, and optionally fetches abstracts/full records in one command.
- A user wants a PubMed literature-review workflow that extracts titles, abstracts, authors, MeSH terms, keywords, and article IDs into structured JSON/JSONL.
- A user wants a time-bounded PubMed research update brief, such as "show me the last 7 days of CRISPR progress" or "summarize the last month of base editing papers."
- A user wants to retrieve records in batches, page through results, or use the Entrez History server (`WebEnv` + `query_key`) instead of issuing one request per ID.
- A user wants the exact request URL, method, and parameters before making the network call.

## Inputs

- Required:
  - target endpoint: `info`, `search`, `summary`, `fetch`, `link`, or `post`
  - target database, such as `pubmed`, `gene`, `protein`, `nuccore`, or another Entrez database
  - one of:
    - search term for `search`
    - ID list or ID file for `summary`, `fetch`, `link`, and `post`
    - `WebEnv` + `query_key` for history-based `summary`, `fetch`, and `link`
- Optional:
  - for the high-level PubMed flow:
    - search term
    - output directory
    - whether to run `efetch`
    - `efetch` `retmode` / `rettype`, defaulting to PubMed abstract-oriented retrieval
  - for the PubMed review flow:
    - search term
    - output directory
    - optional date and sort filters
    - optional explicit `records.json` / `records.jsonl` output paths
  - for the PubMed update brief flow:
    - topic term, such as `CRISPR`, `base editing`, or `prime editing`
    - relative date window such as 7 or 30 days, or explicit date range
    - maximum number of papers to include
    - output directory and optional markdown brief path
  - `email`, `tool`, and `api_key`
  - `retmode`, `rettype`, `retmax`, `retstart`, `sort`, and date filters
  - output path
  - `--dry-run` to print the exact request plan without making the network call

## Workflow

1. Read [eutilities-reference.md](references/eutilities-reference.md) when endpoint semantics or limits are uncertain.
2. Translate the request into one of the deterministic wrapper commands:
   - `scripts/run.sh info`
   - `scripts/run.sh search`
   - `scripts/run.sh summary`
   - `scripts/run.sh fetch`
   - `scripts/run.sh link`
   - `scripts/run.sh post`
   - `scripts/run.sh pubmed-workflow`
   - `scripts/run.sh pubmed-review`
   - `scripts/run.sh pubmed-update-brief`
3. Include `--email` whenever available. Keep `--tool` set unless the user has a strong reason to override it. Include `--api-key` when higher request throughput is needed.
4. Prefer `search --usehistory y` for large result sets, then continue with `summary` or `fetch` using `--webenv` and `--query-key`.
5. For PubMed-first tasks, prefer `pubmed-workflow` over hand-building three separate commands unless the user explicitly wants raw endpoint-level control.
6. For literature-review preparation, prefer `pubmed-review`; it performs PubMed retrieval and extracts structured records from `efetch` XML.
7. For recurring "latest progress" requests, prefer `pubmed-update-brief`; it writes a deterministic `brief.md` draft plus the raw retrieval artifacts.
8. Use `--dry-run` before live calls when the user wants to inspect or approve the request shape.
9. For long ID lists or `--id-file`, let the script auto-select `POST`.
10. Report the exact command, endpoint, database, key parameters, and where the response was written.

## Output Contract

- Exact command(s) run
- Endpoint name and target database(s)
- Key request parameters:
  - search term, IDs, or history parameters
  - `retmode` / `rettype`
  - paging controls such as `retmax` and `retstart`
- Response destination:
  - inline output summary, or
  - saved file path
- For `pubmed-workflow`:
  - `esearch.json`
  - `esummary.json` when hits are returned
  - `efetch.*` when `--include-fetch yes`
  - `manifest.json` describing counts, IDs, `WebEnv`, `query_key`, and output paths
- For `pubmed-review`:
  - `esearch.json`
  - `esummary.json`
  - `efetch.xml`
  - `records.json`
  - `records.jsonl`
  - `manifest.json`
- For `pubmed-update-brief`:
  - `esearch.json`
  - `esummary.json`
  - `efetch.xml`
  - `records.json`
  - `records.jsonl`
  - `brief.md`
  - `manifest.json`
- For history workflows:
  - whether the response contains `WebEnv` / `query_key`
  - the recommended next command
- When `--dry-run` is used:
  - request method
  - request URL
  - request body when applicable

## Limits

- This skill depends on live access to `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/`.
- NCBI recommends no more than 3 requests per second without an API key, and up to 10 requests per second by default with an API key.
- `EFetch` output formats vary by database; `retmode` and `rettype` must match what the target database supports.
- JSON output is not uniformly available for every endpoint/database combination, so XML or text may still be required.
- Common failure cases:
  - missing or wrong `db`
  - providing IDs when the workflow should use `WebEnv` + `query_key`, or vice versa
  - omitting `email` / `tool` in repeated or high-volume use
  - exceeding NCBI rate limits
  - assuming `retmode=json` is available for every request
  - trying to retrieve large result sets one ID at a time instead of using history
