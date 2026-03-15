# DESeq2 and edgeR Differential Expression Reference

## DESeq2 Core Workflow

```r
library(DESeq2)

# From a raw count matrix
dds <- DESeqDataSetFromMatrix(
  countData = count_matrix,   # rows = genes, cols = samples (raw integers)
  colData   = sample_info,    # data.frame with sample metadata
  design    = ~ condition
)

# Filter low-count genes before fitting (speeds up computation)
dds <- dds[rowSums(counts(dds)) >= 10, ]

# Estimate size factors, dispersions, and fit GLM
dds <- DESeq(dds)

# Extract results for a specific contrast
res <- results(dds,
               contrast = c("condition", "treated", "control"),
               alpha = 0.05)

# Shrink LFC for visualization and ranking (use apeglm — most accurate)
res_shrunk <- lfcShrink(dds, coef = "condition_treated_vs_control",
                        type = "apeglm")
```

## DESeq2 Output Columns

| Column | Description |
|--------|-------------|
| `baseMean` | Average normalized count across all samples |
| `log2FoldChange` | Estimated log2 fold change (A vs B) |
| `lfcSE` | Standard error of the LFC estimate |
| `stat` | Wald test statistic |
| `pvalue` | Raw p-value |
| `padj` | Benjamini-Hochberg adjusted p-value |

`padj = NA` means the gene was excluded from testing: either all counts are zero, or it was flagged as a count outlier by Cook's distance filtering.

## DESeq2 with tximport (Salmon/kallisto Input)

```r
library(tximport)

txi <- tximport(files, type = "salmon", tx2gene = tx2gene)

# DESeqDataSetFromTximport applies length-bias correction automatically
dds <- DESeqDataSetFromTximport(txi,
                                colData = sample_info,
                                design  = ~ condition)
```

Do not round `txi$counts` manually — `DESeqDataSetFromTximport` handles the offset internally.

## edgeR Core Workflow

```r
library(edgeR)

dge <- DGEList(counts = count_matrix, group = sample_info$condition)

# Filter lowly expressed genes
keep <- filterByExpr(dge)
dge  <- dge[keep, , keep.lib.sizes = FALSE]

# TMM normalization
dge <- calcNormFactors(dge)

# Build design matrix and estimate dispersions
design <- model.matrix(~ condition, data = sample_info)
dge    <- estimateDisp(dge, design)

# Quasi-likelihood F-test (preferred over likelihood ratio test)
fit <- glmQLFit(dge, design)
qlf <- glmQLFTest(fit, coef = 2)   # coef 2 = second column of design matrix

# Extract all results
results <- topTags(qlf, n = Inf)$table
```

## edgeR with tximport

```r
txi <- tximport(files, type = "salmon", tx2gene = tx2gene,
                countsFromAbundance = "lengthScaledTPM")

dge <- DGEList(counts = txi$counts, group = sample_info$condition)

# Apply effective length offset to account for transcript length variation
dge$offset <- log(txi$length / exp(rowMeans(log(txi$length))))
```

## Batch Correction

```r
# Include batch in the design formula (correct for in the model)
design <- model.matrix(~ batch + condition, data = sample_info)

# For visualization only (PCA, heatmaps) — remove batch effect from expression values
library(limma)
logcpm_corrected <- removeBatchEffect(cpm(dge, log = TRUE),
                                      batch = sample_info$batch)
```

Do not use batch-corrected values as input to DESeq2 or edgeR; only correct in the design matrix.

## Minimum Replicates

| Tool | Minimum | Recommended |
|------|---------|-------------|
| DESeq2 | 2 per group | 3+ per group |
| edgeR | 1 per group (unreliable) | 3+ per group |

With fewer than 3 replicates per group, dispersion estimates are unstable and FDR control is unreliable.

## Quick Comparison: DESeq2 vs edgeR

| Aspect | DESeq2 | edgeR |
|--------|--------|-------|
| Normalization | Median-of-ratios | TMM |
| Dispersion | Per-gene with shrinkage | Tagwise with prior |
| Test | Wald or LRT | Quasi-likelihood F-test (QLF) or LRT |
| LFC shrinkage | `lfcShrink` (apeglm) | None built-in |
| Speed | Slower on large matrices | Faster |

## Common Gotchas

- Both tools require raw integer counts — do not input TPM, FPKM, or normalized values; these violate the negative binomial model assumptions
- Wrong strandedness in the counting step (featureCounts/HTSeq) propagates silently; verify strandedness with RSeQC before counting
- Pre-filtering (`rowSums >= 10`) is not strictly required but substantially reduces computation time and multiple testing burden
- `padj = NA` is expected for all-zero genes or outliers; do not treat these as significant or remove them before passing counts to DESeq2
- `lfcShrink` with `type="apeglm"` requires specifying `coef` by name (from `resultsNames(dds)`), not a `contrast` vector
- For multi-factor designs, set the reference level explicitly: `dds$condition <- relevel(dds$condition, ref = "control")`
