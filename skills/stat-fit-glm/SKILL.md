---
name: stat-fit-glm
description: Fit a generalized linear model (Poisson, Binomial, or Gaussian family) for count or non-normally distributed outcome data.
---

# Skill: Generalized Linear Model

## Use When

- User has count data (e.g., read counts, event counts) requiring Poisson or negative binomial regression
- User has a proportion or binary outcome requiring binomial regression
- User wants a unified framework for regression across different data distributions
- Use cases: RNA-seq count modeling, species abundance counts, clinical event rates

## Inputs

- Required:
  - Data table (CSV or TSV) with a response variable and one or more predictor columns
  - Response variable name
  - Predictor variable name(s)
  - GLM family: `poisson`, `binomial`, or `gaussian`
- Optional:
  - Link function: default per family (`log` for Poisson, `logit` for Binomial, `identity` for Gaussian)
  - Offset variable name (for Poisson rate models, e.g., log library size)
  - Check overdispersion: `true` (default for Poisson)
  - Output directory (default: `./glm_output`)

## Workflow

1. Read data; validate that response variable is compatible with the specified family (non-negative integers for Poisson, 0/1 or proportions for Binomial).
2. Fit GLM using the specified family and link function.
3. If Poisson: test for overdispersion (dispersion statistic). If overdispersed, automatically refit with quasi-Poisson or negative binomial and report.
4. Report for each coefficient: estimate (on link scale), standard error, z-statistic, p-value, exponentiated estimate (rate ratio for log link, odds ratio for logit link) with 95% CI.
5. Report model fit: null deviance, residual deviance, AIC, degrees of freedom.
6. Generate diagnostic plots: residuals vs. fitted (Pearson residuals), Q-Q plot of deviance residuals.
7. Write results table (TSV), model summary (text), and diagnostic plots (PDF) to output directory.
8. Report overdispersion finding and family choice justification.

## Output Contract

- Coefficient table (TSV): term, estimate, std_error, z_statistic, p_value, exp_estimate, ci_lower, ci_upper
- Model fit summary (TSV): family, link, null_deviance, residual_deviance, aic, df_residual
- Diagnostic plots (PDF)
- Overdispersion test result (Poisson only, printed to stdout)

## Limits

- Negative binomial GLM is preferred over Poisson when count data is overdispersed (common in RNA-seq — use DESeq2 instead for that use case).
- Binomial GLM requires the response to be a proportion [0,1] or a two-column success/failure matrix for aggregated data.
- Does not handle zero-inflated data; use hurdle or zero-inflated models separately.
- Common failure: passing a continuous response with Poisson family — verify data type before running.
