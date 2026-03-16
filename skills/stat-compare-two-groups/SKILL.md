---
name: stat-compare-two-groups
description: Compare a continuous variable between two groups with automatic selection of t-test, Welch test, or Mann-Whitney U test based on data properties.
---

# Skill: Two-Group Statistical Comparison

## Use When

- User wants to test whether a continuous measurement differs between two experimental groups (e.g., treated vs. control, knockout vs. wild-type)
- User needs a p-value, effect size, and confidence interval for a two-group comparison
- User is unsure which statistical test is appropriate and wants automatic method selection

## Inputs

- Required:
  - Data table (CSV or TSV) with a numeric value column and a group column (exactly two group levels)
- Optional:
  - Group variable column name (default: auto-detected if only one non-numeric column)
  - Value variable column name (default: auto-detected if only one numeric column)
  - Paired comparison: `true` or `false` (default: `false`)
  - Alternative hypothesis: `two-sided` (default), `greater`, or `less`
  - Output directory (default: `./compare_output`)

## Workflow

1. Read data; validate that group column has exactly two levels.
2. Run normality test (Shapiro-Wilk) on each group separately.
3. If both groups are normal: run Levene's test for equal variance.
   - Equal variance (p > 0.05): Student's t-test.
   - Unequal variance (p ≤ 0.05): Welch's t-test.
4. If either group is non-normal: Mann-Whitney U test (unpaired) or Wilcoxon signed-rank test (paired).
5. Compute effect size: Cohen's d (parametric) or rank-biserial correlation r (non-parametric).
6. Compute 95% confidence interval for the difference in means (parametric) or Hodges-Lehmann estimator (non-parametric).
7. Generate a box plot with individual data points and significance annotation.
8. Write a structured result and plot (PDF) to output directory.
9. Report method used, test statistic, p-value, effect size, confidence interval, and interpretation.

## Output Contract

- Result (TSV): group1, group2, method_used, statistic, p_value, effect_size, effect_size_type, ci_lower, ci_upper, n_group1, n_group2
- Box plot with data points (PDF)
- Decision log explaining method selection (printed to stdout)

## Limits

- Requires exactly two groups; use `stat-compare-multiple-groups` for three or more groups.
- Minimum recommended sample size: n ≥ 5 per group (results are unreliable below this).
- Paired comparison requires equal sample sizes in both groups.
- Common failure: group column contains more than two levels — filter data before running.
