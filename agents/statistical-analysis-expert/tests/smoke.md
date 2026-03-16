# Smoke Tests

## Scenario 1: Two-Group Comparison with Automatic Method Selection

**Input**: "I have a CSV with two columns: `group` (A or B) and `expression_level`. I want to know if the groups differ."

**Expected**:
- Agent inspects the data and reports n per group.
- Runs `stat-assess-data-quality` then `stat-analyze-distribution` on `expression_level` per group.
- Runs `stat-compare-two-groups`, which internally applies Shapiro-Wilk and selects t-test or Mann-Whitney.
- Reports which test was selected and why (cites normality test result).
- Delivers: p-value, effect size (Cohen's d or rank-biserial r), 95% CI, box plot.
- Does NOT just say "I ran a t-test" without checking assumptions.

---

## Scenario 2: Multi-Group Comparison with Post-Hoc

**Input**: "I have expression data for four treatment groups. I want to know which groups are different from each other."

**Expected**:
- Agent runs `stat-analyze-distribution` to assess normality within each group.
- Runs `stat-compare-multiple-groups`, which selects one-way ANOVA (if normal) or Kruskal-Wallis (if not).
- Reports omnibus test result (F-statistic or H-statistic, p-value, eta-squared / epsilon-squared).
- Runs post-hoc test (Tukey HSD or Dunn) and reports all pairwise comparisons with adjusted p-values.
- Produces a box plot with significance brackets.

---

## Scenario 3: Linear Regression with Assumption Check

**Input**: "Fit a linear model predicting protein concentration from gene expression and age."

**Expected**:
- Agent asks which column is the response and which are predictors (or infers from context).
- Runs `stat-fit-linear-model`.
- Reports coefficients, standard errors, p-values, R², and 95% CIs.
- Runs and reports residual diagnostic tests (Shapiro-Wilk on residuals, Breusch-Pagan for homoscedasticity, Cook's distance for influential points).
- If any assumption is violated, flags it and explains the implication (e.g., "residuals are heteroscedastic; consider robust standard errors or a log-transformation of the response").
- Produces 4-panel residual diagnostic plot.

---

## Scenario 4: PCA Followed by Clustering

**Input**: "I have a 200-sample × 5000-gene expression matrix. I want to see if there are any natural groupings."

**Expected**:
- Agent does NOT immediately cluster the 5000-gene matrix.
- Runs `stat-pca` first (reducing to top 50 PCs); produces PCA scatter plot.
- Identifies how many PCs explain ≥ 80% of variance.
- Runs `stat-cluster-samples` on PCA coordinates; uses elbow method to select k; reports silhouette scores.
- Explains: "Clustering was performed on PC coordinates rather than raw gene expression to reduce noise and computational cost."
- Optionally offers `stat-nonlinear-embedding` for UMAP visualization colored by cluster label.

---

## Scenario 5: Survival Analysis

**Input**: "I have a clinical dataset with columns `os_days` (overall survival in days), `os_event` (1 = death, 0 = censored), and `treatment` (A or B). I want to compare survival between the two treatment arms."

**Expected**:
- Agent validates that `os_event` is binary and `os_days` is non-negative.
- Runs `stat-survival-analysis` with group column = `treatment`.
- Reports Kaplan-Meier curves with confidence intervals for both groups.
- Reports median survival time per group with 95% CI.
- Reports log-rank test chi-square, df, and p-value.
- Produces KM plot with at-risk table.
- Notes: "The log-rank test assumes proportional hazards; if the curves cross, consider a weighted test."

---

## Scenario 6: Ambiguous Request — Wrong Method for Data Type

**Input**: "My outcome is whether a patient responded (yes/no). Run a linear regression to predict response from biomarker levels."

**Expected**:
- Agent flags that a binary outcome is not appropriate for linear regression.
- Explains: "Linear regression on a binary outcome produces probabilities outside [0,1] and violates the normality assumption. Logistic regression is the correct method here."
- Redirects to `stat-logistic-regression`.
- Does NOT run linear regression as requested without flagging the issue.

---

## Scenario 7: Underpowered Analysis

**Input**: "I have 3 samples in group A and 3 in group B. Can you compare them?"

**Expected**:
- Agent flags small sample size (n = 3 per group) as underpowered.
- Notes that Shapiro-Wilk has low power at n = 3 and normality cannot be reliably assessed.
- Proceeds with Mann-Whitney U (non-parametric, no normality assumption) as the safer choice.
- Reports the result with an explicit caveat: "With n = 3 per group, this test has very low statistical power. A p-value > 0.05 should not be interpreted as evidence of no difference."
- Does NOT silently run a t-test on 3 samples.
