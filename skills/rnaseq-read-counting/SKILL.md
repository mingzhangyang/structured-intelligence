---
name: rnaseq-read-counting
description: Generate gene-level read count matrices from aligned BAMs using featureCounts or HTSeq-count.
---

# Skill: RNA-seq Read Counting

## Use When

- User has aligned BAMs and needs a gene-level count matrix for differential expression
- User wants to count reads per gene feature from GTF annotation
- User needs to handle strandedness correctly
- User wants to count multiple BAMs into a single matrix

## Inputs

- Required:
  - BAM file(s) (one or more coordinate-sorted BAMs)
  - GTF annotation file
- Optional:
  - Tool choice: `featurecounts` or `htseq` (default: `featurecounts`)
  - Strandedness: `0` = unstranded, `1` = stranded, `2` = reverse-stranded (default: `0`)
  - Feature type to count (default: `exon`)
  - Attribute for grouping (default: `gene_id`)
  - Number of threads (default: 4)
  - Output path
  - Paired-end flag
  - Minimum mapping quality

## Workflow

1. Validate BAM files are sorted and indexed.
2. Determine strandedness if not specified (recommend checking with RSeQC `infer_experiment.py`).
3. If featureCounts: run with `-T threads`, `-s strandedness`, `-a GTF`, `-o output`. For multiple BAMs, featureCounts natively produces a multi-sample count matrix.
4. If HTSeq-count: run `htseq-count` with `--stranded`, `--type`, `--idattr`. For multiple BAMs, run per-sample then merge columns into a single matrix.
5. For multi-BAM input: featureCounts natively produces a matrix; HTSeq-count requires per-sample runs then merge.
6. Report: total assigned reads, unassigned categories (ambiguous, multimapping, no feature), assignment rate per sample.

## Output Contract

- Count matrix: TSV file with gene IDs as rows and samples as columns
- Count summary statistics (featureCounts `.summary` file or HTSeq-count footer)
- Per-sample assignment rates

## Limits

- featureCounts is multi-threaded and faster; HTSeq-count is single-threaded.
- Strandedness must match library prep protocol or counts will be incorrect.
- featureCounts is part of the Subread package and must be installed.
- BAMs must be coordinate-sorted.
- Common failure cases: wrong strandedness setting, unsorted BAMs, GTF/BAM chromosome naming mismatch.
