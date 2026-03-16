---
name: stat-assess-data-quality
description: Assess data quality by reporting missing values, outliers, sample size, and variance structure for each variable in a table.
---

# Skill: Statistical Data Quality Assessment

## Use When

- User wants a quick data quality report before any statistical analysis
- User needs to identify columns with high missingness or extreme outliers
- User wants to understand variance structure and flag zero-variance or near-zero-variance columns
- User is preparing data for modeling and wants a pre-flight check

## Inputs

- Required:
  - Data table (CSV or TSV)
- Optional:
  - Outlier detection method: `iqr` (default) or `zscore`
  - IQR multiplier for outlier threshold (default: `1.5`)
  - Z-score threshold (default: `3.0`)
  - Output directory (default: `./qc_output`)

## Workflow

1. Read the data file; record total rows (n) and total columns.
2. For each column, report: data type, non-missing count, missing count, missing rate (%).
3. For numeric columns: compute mean, SD, min, max; detect outliers using IQR fence or Z-score; report outlier count and outlier rate (%).
4. Flag columns with: missing rate > 20%, outlier rate > 5%, zero variance, near-zero variance (coefficient of variation < 0.01).
5. Report sample size adequacy: flag if n < 30 (small sample warning).
6. Produce a missingness heatmap (rows = samples, columns = variables) if any missing values exist.
7. Write a quality report (TSV) and missingness plot (PDF) to output directory.
8. Summarize flags: list columns requiring attention and recommended actions (imputation, removal, transformation).

## Output Contract

- Quality report table (TSV): column, dtype, n_non_missing, n_missing, missing_rate, n_outliers, outlier_rate, mean, sd, min, max, flags
- Missingness heatmap (PDF, only if missing values present)
- Summary of flagged columns (printed to stdout)

## Limits

- IQR-based outlier detection assumes roughly unimodal distributions; may flag many values in skewed data.
- Does not impute or remove data — assessment only.
- Very large datasets (> 1M rows) may be slow; consider sampling first.
- Common failure: mixed-type columns (e.g., numeric with "N/A" strings) require preprocessing.
