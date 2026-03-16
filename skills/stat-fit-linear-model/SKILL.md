---
name: stat-fit-linear-model
description: Fit a linear regression model, report coefficients and model fit, and generate residual diagnostic plots.
---

# Skill: Linear Regression Modeling

## Use When

- User wants to model the linear relationship between a continuous outcome and one or more predictors
- User needs coefficient estimates, confidence intervals, and p-values for each predictor
- User wants to assess model fit (R², adjusted R²) and check regression assumptions
- Use cases include: gene expression vs. age, protein concentration vs. metabolic rate, any dose-response relationship

## Inputs

- Required:
  - Data table (CSV or TSV) with a numeric response variable and one or more numeric or categorical predictor columns
  - Response (outcome) variable name
  - Predictor variable name(s)
- Optional:
  - Interaction terms (e.g., `var1:var2`)
  - Standardize predictors: `true` or `false` (default: `false`)
  - Output directory (default: `./lm_output`)

## Workflow

1. Read data; validate that response and predictor columns exist and are appropriate types.
2. Encode categorical predictors as dummy variables (reference level = first alphabetical level).
3. Fit the linear model: `response ~ predictors` using ordinary least squares.
4. Report for each coefficient: estimate, standard error, t-statistic, p-value, 95% confidence interval.
5. Report model fit: R², adjusted R², F-statistic, overall p-value, AIC, BIC.
6. Generate residual diagnostic plots: (a) residuals vs. fitted, (b) Q-Q plot of residuals, (c) scale-location, (d) Cook's distance.
7. Test regression assumptions: normality of residuals (Shapiro-Wilk), homoscedasticity (Breusch-Pagan), absence of influential points (Cook's distance > 4/n).
8. Write results table (TSV), model summary (text), and diagnostic plots (PDF) to output directory.

## Output Contract

- Coefficient table (TSV): term, estimate, std_error, t_statistic, p_value, ci_lower, ci_upper
- Model fit summary (TSV): r_squared, adj_r_squared, f_statistic, f_p_value, aic, bic, n
- Residual diagnostic plots (PDF, 4-panel)
- Assumption test results (printed to stdout)

## Limits

- Assumes linearity, independence, homoscedasticity, and normality of residuals — check diagnostic plots.
- Does not handle multicollinearity automatically; check VIF (variance inflation factor) separately if many predictors.
- Not suitable for count data, binary outcomes, or data with heavy censoring — use `stat-fit-glm` instead.
- Common failure: near-perfect multicollinearity among predictors causes singular matrix error.
