---
name: stat-pca
description: Perform PCA on a numeric data matrix to reduce dimensionality, visualize sample structure, and identify top contributing features.
---

# Skill: Principal Component Analysis

## Use When

- User wants to explore sample structure or batch effects in high-dimensional data (RNA-seq, proteomics, metabolomics)
- User needs dimensionality reduction before clustering or modeling
- User wants to identify which features (genes, proteins) drive sample separation
- User wants a PCA plot colored by sample metadata

## Inputs

- Required:
  - Data matrix (CSV or TSV): rows = samples, columns = features (or transposed — specify orientation)
- Optional:
  - Matrix orientation: `samples_as_rows` (default) or `samples_as_columns`
  - Number of PCs to compute (default: `10` or min(n_samples, n_features))
  - Metadata table (CSV or TSV) with sample annotations for plot coloring (must share sample IDs)
  - Color-by column from metadata (default: first metadata column)
  - Scale features before PCA: `true` (default) or `false`
  - Output directory (default: `./pca_output`)

## Workflow

1. Read data matrix; orient so rows = samples.
2. Check for and remove zero-variance features; log-transform if all values are non-negative and range > 100 (log1p).
3. Center and optionally scale features (z-score standardization).
4. Compute PCA using singular value decomposition.
5. Report variance explained per PC; plot scree plot.
6. Extract sample coordinates on PC1–PC10 and feature loadings on PC1–PC5.
7. Plot PC1 vs. PC2 scatter; if metadata provided, color by specified annotation column; label outlier samples.
8. Report top 20 features with highest absolute loading on PC1 and PC2.
9. Write PC coordinates (TSV), loadings (TSV), variance explained (TSV), scree plot (PDF), and PCA scatter plot (PDF) to output directory.

## Output Contract

- PC coordinates table (TSV): sample_id, PC1, PC2, ..., PC10
- Feature loadings table (TSV): feature_id, PC1_loading, PC2_loading, ..., PC5_loading
- Variance explained table (TSV): PC, variance_explained, cumulative_variance
- Scree plot (PDF)
- PCA scatter plot (PDF, PC1 vs. PC2)

## Limits

- PCA is a linear method; nonlinear structure may not be captured — use `stat-nonlinear-embedding` for t-SNE/UMAP.
- Features must outnumber the number of components requested; otherwise reduce n_components.
- Scaling is critical when features have different units or dynamic ranges.
- Common failure: sample ID mismatch between data matrix and metadata table.
