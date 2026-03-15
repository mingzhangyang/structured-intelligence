---
name: rnaseq-transcript-quantification
description: Alignment-free transcript-level quantification using Salmon or kallisto for fast and accurate RNA-seq expression estimates.
---

# Skill: RNA-seq Transcript Quantification

## Use When

- User wants fast transcript-level quantification without genome alignment
- User wants TPM and count estimates per transcript
- User needs input for downstream differential expression analysis (tximport/tximeta in R)
- User wants to compare Salmon vs kallisto quantification

## Inputs

- Required:
  - Trimmed FASTQ file(s) (single-end or paired-end)
  - Transcriptome index (Salmon index directory or kallisto index file)
- Optional:
  - Tool choice: `salmon` or `kallisto` (default: `salmon`)
  - Library type for Salmon (default: `A` for auto-detect)
  - Number of threads (default: 4)
  - Output directory (default: `./quant_output`)
  - Number of bootstrap samples (for downstream use with sleuth)

## Workflow

1. Validate that the transcriptome index exists for the chosen tool.
2. If Salmon: run `salmon quant` with `--validateMappings`, `--seqBias`, and `--gcBias` for bias correction.
3. If kallisto: run `kallisto quant`.
4. If bootstraps are requested: add `--numBootstraps` (Salmon) or `-b` (kallisto).
5. Report: total reads processed, mapping rate, number of quantified transcripts.

## Output Contract

- Quantification file:
  - Salmon: `quant.sf` with columns: Name, Length, EffectiveLength, TPM, NumReads
  - kallisto: `abundance.tsv` with columns: target_id, length, eff_length, est_counts, tpm
- Log file with mapping statistics
- Auxiliary files (Salmon `aux_info/` directory or kallisto `run_info.json`)

## Limits

- Salmon and kallisto must be installed and available on PATH.
- Transcriptome index must be pre-built before running this skill.
- Quantification is at the transcript level; use tximport in R to summarize to gene level for DE analysis.
- Not suitable for novel transcript or isoform discovery.
- For single-end reads with kallisto, fragment length and standard deviation must be provided.
- Common failure cases:
  - Transcriptome index built from a different annotation version than expected, skewing quantification.
  - Salmon library type auto-detection failing on very low-read-count samples.
  - kallisto single-end mode missing required `--fragment-length` and `--sd` parameters.
