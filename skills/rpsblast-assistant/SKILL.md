---
name: rpsblast-assistant
description: Use natural language to prepare, run, and interpret standalone rpsblast, rpstblastn, and rpsbproc workflows against NCBI CDD assets.
---

# Skill: rpsblast-assistant

## Use When

- A user wants to install or prepare standalone `rpsblast`, `rpstblastn`, or `rpsbproc`.
- A user wants the agent to download and unpack the CDD databases or `rpsbproc` annotation files.
- A user wants to run CDD/RPS-BLAST locally from natural language instead of hand-writing commands.
- A user needs help understanding which files are required, how to structure the project folder, or what output formats are produced.
- A user wants the post-processed tabular annotations from `rpsbproc`, not just raw BLAST output.

## Inputs

- Required:
  - query FASTA path, sequence text, or a request to prepare the environment only
- Optional:
  - query type: `protein` or `nucleotide`
  - database prefix, usually `db/Cdd`
  - output prefix
  - E-value threshold
  - whether to run `rpsbproc`
  - location of local binaries or downloaded archives

## Workflow

1. If the request is about installation or setup, read [rpsblast-reference.md](references/rpsblast-reference.md).
2. Prefer the canonical local pipeline:
   - `scripts/run.sh sources` to print acquisition URLs.
   - `scripts/run.sh download --db-dir db --data-dir data` to fetch and unpack the CDD database and annotation files.
   - `scripts/run.sh check --db-prefix <prefix> --data-dir <dir>` to verify a local setup.
   - `scripts/run.sh run --query <fasta> --db-prefix <prefix> --out-prefix <prefix>` to execute the pipeline.
3. Translate natural language into explicit parameters:
   - default to `protein` unless the user clearly asks for nucleotide queries
   - use `rpsblast` for proteins and `rpstblastn` for nucleotide input
   - default E-value to `0.01` for the paper's standard local workflow unless the user requests another threshold
   - default to post-processing with `rpsbproc`
   - for database download requests, default to `--db-set minimal` unless the user asks for the full external-source collection
4. If `rpsbproc` will be used, force `rpsblast`/`rpstblastn` output to ASN.1 archive format with `-outfmt 11` and save it as `<prefix>.asn`.
5. Run `rpsbproc` on the ASN.1 file to produce `<prefix>.out`.
6. Report:
   - exact command(s) run
   - generated file paths
   - whether the final result is raw ASN.1 archive output or post-processed tab-delimited annotations
   - for `rpsbproc` output, mention that the file begins with comment/template lines starting with `#` and then a structured data section
   - a brief interpretation of the result file
7. If the environment is incomplete, stop and tell the user exactly which binary, database, or data file is missing.

## Output Contract

- Setup guidance that names the source URLs for:
  - BLAST+ executables containing `rpsblast`/`rpstblastn`
  - `rpsbproc`
  - CDD `little_endian` databases
  - CDD annotation/data files
- A runnable command line or a completed execution using `scripts/run.sh`
- For download flows, a populated `db/` and optionally `data/` directory, plus the original archives under a download cache directory
- Generated files, typically:
  - `<prefix>.asn`: ASN.1 archive output from `rpsblast`/`rpstblastn`
  - `<prefix>.out`: tab-delimited flat file from `rpsbproc`, with a comment/template header and a data section delimited by `DATA` and `ENDDATA`
- A short natural-language summary of what the output means

## Limits

- This skill does not bundle NCBI binaries or CDD databases.
- The download helper fetches official public files but still depends on local network access and the NCBI FTP/HTTPS endpoints being reachable.
- `rpsbproc` requires raw `rpsblast`/`rpstblastn` output in ASN.1 archive format; plain text or tabular BLAST output is not sufficient for post-processing.
- `rpsbproc` output is not just a plain spreadsheet dump; parsers should ignore leading `#` comment/template lines and read the structured data section.
- The paper notes that standalone `rpsblast` is time-consuming for large batches; use expectations accordingly.
- Common failure cases:
  - downloading only databases but forgetting the annotation files needed by `rpsbproc`
  - using the wrong executable for query type
  - pointing `-db` at the directory instead of the database prefix
  - forgetting the CDD annotation files required by `rpsbproc`
  - emitting the wrong `-outfmt` when `rpsbproc` is needed
  - assuming the final `.out` file is BLAST pairwise text rather than tab-delimited annotations
