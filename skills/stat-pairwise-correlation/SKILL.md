---
name: stat-pairwise-correlation
description: Compute pairwise correlations and significance tests across all numeric variables, and produce a correlation heatmap.
---

# Skill: Pairwise Correlation Analysis

## Use When

- User wants to scan for linear or monotonic relationships among multiple numeric variables
- User needs a correlation matrix with p-values for gene expression, neural activity, or metabolomics data
- User wants to identify highly correlated features before modeling (collinearity check)
- User is building a co-expression or co-activity network

## Inputs

- Required:
  - Data matrix (CSV or TSV): rows = observations, columns = numeric variables
- Optional:
  - Correlation method: `pearson` (default), `spearman`, or `kendall`
  - Multiple-testing correction method: `fdr` (Benjamini-Hochberg, default) or `bonferroni`
  - Significance threshold for highlighting (default: `0.05`)
  - Output directory (default: `./corr_output`)

## Workflow

1. Read the data matrix; keep only numeric columns.
2. Compute the full pairwise correlation matrix using the specified method.
3. Compute p-values for each pair using the appropriate test (Pearson: t-distribution; Spearman/Kendall: permutation or asymptotic).
4. Apply multiple-testing correction across all variable pairs.
5. Generate a correlation heatmap: color-coded by correlation coefficient, asterisks for significant pairs (adjusted p < threshold).
6. Generate a scatter plot matrix (pairs plot) for datasets with ≤ 10 variables.
7. Report the top 20 strongest positive and top 20 strongest negative correlations.
8. Write correlation matrix (TSV), adjusted p-value matrix (TSV), and plots (PDF) to output directory.

## Output Contract

- Correlation matrix (TSV): variable × variable, values = correlation coefficients
- Adjusted p-value matrix (TSV): variable × variable, values = corrected p-values
- Correlation heatmap (PDF)
- Pairs plot (PDF, only if ≤ 10 variables)
- Top correlations summary table (TSV): var1, var2, correlation, p_value, adj_p_value

## Limits

- Pearson correlation assumes linearity; use Spearman or Kendall for non-linear monotonic relationships or ordinal data.
- Correlation does not imply causation.
- Kendall's tau is slow for n > 10000; Spearman is preferred for large samples.
- Common failure: constant or near-constant columns produce undefined correlations — remove before running.
