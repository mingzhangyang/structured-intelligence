---
name: rnaseq-differential-expression
description: Statistical differential expression analysis using DESeq2 or edgeR in R, with support for count matrix or tximport input.
---

# Skill: RNA-seq Differential Expression

## Use When

- User has a count matrix or transcript quantification and wants to find differentially expressed genes
- User wants to perform statistical DE testing with proper normalization
- User needs volcano plots, MA plots, PCA, and heatmaps
- User wants to compare DESeq2 vs edgeR results

## Inputs

- Required:
  - Count matrix (TSV with gene IDs as rows, samples as columns) OR Salmon/kallisto quantification directories plus a tx2gene mapping file
  - Sample metadata (TSV with columns: sample_id, condition, and optionally batch)
- Optional:
  - Tool choice: `deseq2` or `edger` (default: `deseq2`)
  - Contrast: condition levels to compare (e.g., `treated,control`)
  - FDR threshold (default: `0.05`)
  - log2 fold-change threshold (default: `1`)
  - Output directory (default: `./de_output`)

## Workflow

1. Read count matrix or import transcript-level estimates via tximport.
2. Read sample metadata and validate that sample IDs match between counts and metadata.
3. Build design formula (`~ condition`, or `~ batch + condition` if batch column is provided).
4. If DESeq2: create `DESeqDataSetFromMatrix` (or `DESeqDataSetFromTximport`), run `DESeq()`, extract `results()`.
5. If edgeR: create `DGEList`, `calcNormFactors`, `estimateDisp`, `glmQLFit`, `glmQLFTest`.
6. Extract results: gene ID, log2 fold-change, p-value, adjusted p-value, baseMean (DESeq2) or logCPM (edgeR).
7. Generate plots: PCA of samples, volcano plot, MA plot, heatmap of top DE genes.
8. Write results table sorted by adjusted p-value.
9. Report: total genes tested, number significant (up-regulated and down-regulated), summary of top hits.

## Output Contract

- DE results table (TSV): gene_id, log2FoldChange, pvalue, padj, baseMean/logCPM
- PCA plot (PDF)
- Volcano plot (PDF)
- MA plot (PDF)
- Heatmap of top DE genes (PDF)
- Normalized count matrix (TSV)
- R session info (text file)

## Limits

- Requires R with DESeq2 or edgeR installed (Bioconductor packages).
- Minimum 3 biological replicates per condition recommended for reliable statistics.
- Not suitable for single-cell RNA-seq without modifications.
- Python alternative: PyDESeq2 for DESeq2-equivalent analysis.
- Common failure cases: sample ID mismatch between counts and metadata, too few replicates, incorrect contrast specification.
