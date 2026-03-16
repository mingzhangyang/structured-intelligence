---
name: stat-survival-analysis
description: Estimate and compare survival functions using Kaplan-Meier curves and log-rank test, with optional Cox proportional hazards regression.
---

# Skill: Survival Analysis

## Use When

- User wants to analyze time-to-event data (overall survival, disease-free survival, time to relapse)
- User wants to compare survival curves between two or more groups (e.g., high vs. low expression, treated vs. untreated)
- User wants to identify predictors of survival using multivariable Cox regression
- Use cases: clinical trial outcomes, patient survival, cancer prognosis

## Inputs

- Required:
  - Data table (CSV or TSV) with: time-to-event column (numeric), event indicator column (1 = event occurred, 0 = censored)
  - Time column name
  - Event column name
- Optional:
  - Group column name for Kaplan-Meier comparison and log-rank test (if omitted: single KM curve)
  - Covariate column names for Cox regression (if provided: runs multivariable Cox model)
  - Time unit label (default: `days`)
  - Output directory (default: `./survival_output`)

## Workflow

1. Read data; validate that time column is non-negative numeric and event column is binary (0/1).
2. Compute Kaplan-Meier survival estimate for each group (or overall if no group column).
3. Report median survival time and 95% confidence interval (Greenwood formula) per group.
4. If multiple groups: run log-rank test (Mantel-Cox); report chi-square statistic and p-value.
5. Generate Kaplan-Meier plot with confidence intervals, censoring tick marks, and at-risk table.
6. If covariate columns provided:
   a. Fit Cox proportional hazards model.
   b. Test proportional hazards assumption (Schoenfeld residuals).
   c. Report for each covariate: hazard ratio, 95% CI, z-statistic, p-value.
   d. Generate forest plot of hazard ratios.
7. Write results and plots (PDF) to output directory.

## Output Contract

- KM table (TSV): time, survival_probability, ci_lower, ci_upper, n_at_risk, n_events, group
- Median survival table (TSV): group, median_survival, ci_lower, ci_upper
- Log-rank test result (TSV): chi_square, df, p_value (if multiple groups)
- Cox regression table (TSV): covariate, hazard_ratio, ci_lower, ci_upper, z_statistic, p_value (if covariates provided)
- Kaplan-Meier plot with at-risk table (PDF)
- Forest plot (PDF, Cox only)

## Limits

- Requires accurate censoring information; informative censoring (censored because of outcome-related reasons) biases results.
- Cox model assumes proportional hazards — verify with Schoenfeld residuals test (p > 0.05 for each covariate).
- Log-rank test has low power when hazard ratio changes over time (crossing survival curves).
- Common failure: event column containing values other than 0/1 (e.g., 2 for competing events) — binarize or use competing risks models.
