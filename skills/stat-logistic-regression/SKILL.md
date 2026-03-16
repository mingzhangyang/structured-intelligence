---
name: stat-logistic-regression
description: Fit a logistic regression model for binary outcomes, report odds ratios and model performance (AUC-ROC, confusion matrix).
---

# Skill: Logistic Regression

## Use When

- User wants to model the probability of a binary outcome (disease/healthy, expressed/not expressed, responder/non-responder)
- User needs odds ratios and their confidence intervals for each predictor
- User wants to evaluate model discrimination with AUC-ROC and calibration
- Common in medical, epidemiological, and genomics classification tasks

## Inputs

- Required:
  - Data table (CSV or TSV) with a binary outcome column (0/1 or two-level factor) and one or more predictor columns
  - Outcome variable name
  - Predictor variable name(s)
- Optional:
  - Regularization: `none` (default), `l1` (Lasso), or `l2` (Ridge)
  - Test set fraction for performance evaluation (default: `0.2`)
  - Output directory (default: `./logit_output`)

## Workflow

1. Read data; validate that outcome column is binary; encode predictors as needed.
2. Split data into training and test sets (stratified by outcome).
3. Fit logistic regression on training set using maximum likelihood estimation.
4. Report for each coefficient: log-odds estimate, standard error, z-statistic, p-value, odds ratio, 95% CI for odds ratio.
5. Evaluate on test set: compute AUC-ROC, plot ROC curve, compute confusion matrix at 0.5 threshold (accuracy, sensitivity, specificity, PPV, NPV).
6. Compute Hosmer-Lemeshow goodness-of-fit test for calibration.
7. If regularization is used: report optimal lambda from cross-validation, coefficients at optimal lambda.
8. Write coefficient table (TSV), performance metrics (TSV), ROC curve plot (PDF), and calibration plot (PDF) to output directory.

## Output Contract

- Coefficient table (TSV): term, log_odds, std_error, z_statistic, p_value, odds_ratio, ci_lower_or, ci_upper_or
- Performance metrics (TSV): auc, accuracy, sensitivity, specificity, ppv, npv, hl_test_p
- ROC curve (PDF)
- Confusion matrix (printed to stdout)

## Limits

- Assumes independence of observations; does not account for clustering or repeated measures.
- Requires sufficient events per variable (EPV ≥ 10 recommended) to avoid overfitting.
- Class imbalance can inflate accuracy; examine sensitivity/specificity and AUC.
- Common failure: outcome column with more than two levels — binarize before running.
