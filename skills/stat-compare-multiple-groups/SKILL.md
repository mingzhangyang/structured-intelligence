---
name: stat-compare-multiple-groups
description: Compare a continuous variable across three or more groups using one-way ANOVA or Kruskal-Wallis with post-hoc testing.
---

# Skill: Multiple-Group Statistical Comparison

## Use When

- User wants to compare a continuous measurement across three or more experimental groups
- User needs an omnibus test (ANOVA or Kruskal-Wallis) plus pairwise post-hoc comparisons
- User has a two-factor design and wants to test for interaction effects (two-way ANOVA)

## Inputs

- Required:
  - Data table (CSV or TSV) with a numeric value column and a group column (three or more levels)
- Optional:
  - Group variable column name
  - Value variable column name
  - Second factor column for two-way ANOVA (optional; triggers two-way analysis)
  - Post-hoc method: `tukey` (default for ANOVA) or `dunn` (default for Kruskal-Wallis)
  - Output directory (default: `./multigroup_output`)

## Workflow

1. Read data; validate that group column has three or more levels.
2. Run normality test (Shapiro-Wilk) and Levene's test for each group.
3. If all groups are normal and variances are approximately equal: one-way ANOVA.
   - If second factor provided: two-way ANOVA with interaction term.
4. If normality or homogeneity of variance is violated: Kruskal-Wallis test.
5. If omnibus test is significant (p < 0.05): run post-hoc pairwise comparisons.
   - ANOVA: Tukey HSD (controls family-wise error rate).
   - Kruskal-Wallis: Dunn test with Benjamini-Hochberg correction.
6. Compute effect size: eta-squared (η²) for ANOVA, epsilon-squared for Kruskal-Wallis.
7. Generate a box plot with all groups and pairwise significance brackets.
8. Write results and plot (PDF) to output directory.
9. Report: omnibus test result, effect size, significant pairwise comparisons.

## Output Contract

- Omnibus test result (TSV): test, statistic, df, p_value, effect_size, effect_size_type
- Post-hoc comparisons table (TSV): group1, group2, statistic, p_value, adj_p_value, significant
- Box plot with significance brackets (PDF)
- Decision log explaining method selection (printed to stdout)

## Limits

- Two-way ANOVA assumes balanced or near-balanced design; unbalanced designs require Type III sums of squares.
- Does not support repeated-measures ANOVA; use specialized tools for within-subject designs.
- Tukey HSD assumes equal group sizes; Games-Howell is preferred for unequal variances.
- Common failure: too few observations per group (n < 5) makes tests unreliable.
