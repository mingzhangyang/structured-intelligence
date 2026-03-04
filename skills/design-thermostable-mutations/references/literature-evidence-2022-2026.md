# Literature Evidence Map (2022-2026)

Use this file when the user asks for deep justification, high-confidence decision support, or "latest" best practices.

## How to apply this evidence

1. Start from objective: thermostability, storage stability, pH tolerance, solvent tolerance, or mechanism probing.
2. Choose tools that match that objective, not a single universal default.
3. Add uncertainty language whenever recommendations rely on known weak regions (stabilizing hits, high-order combinations, interface-only inferred by monomer tools).

## High-impact benchmark signals

### A) DDG predictors remain biased and context-sensitive

- Large-scale benchmark analysis reports strong destabilizing-class tendency and weaker recovery of stabilizing variants, especially for complex mutation settings.
- Practical implication:
  - Treat "predicted stabilizing" as tentative until orthogonal re-scoring or experiment.
  - Use at least two independent predictors before lead selection.

Primary source:
- https://pubmed.ncbi.nlm.nih.gov/40797173/

### B) Additivity assumptions fail often for multi-mutation design

- Modern benchmarking confirms non-additivity/epistasis as a major failure point for naive multi-site scoring.
- Practical implication:
  - Restrict early combinatorial order.
  - Re-score top pairs/triples with orthogonal models.
  - Avoid direct arithmetic extrapolation from single-site DDG values.

Primary source:
- https://pubmed.ncbi.nlm.nih.gov/39229177/

### C) AF3 improves local detail in many settings, but does not remove all global limitations

- Recent AF3 benchmarking highlights gains in local and interaction-relevant structure quality while showing mixed global improvements for some monomer tasks.
- Practical implication:
  - Use AF3/AF pipelines for structural plausibility and local inspection.
  - Do not infer stability ranking from AF confidence metrics alone.

Primary source:
- https://pubmed.ncbi.nlm.nih.gov/39704075/

### D) Thermostability pipelines should integrate temperature-aware evidence

- Recent reviews emphasize integrating classical DDG signals with temperature-oriented predictors and assay-aware interpretation.
- Practical implication:
  - For thermostability objectives, avoid DDG-only ranking.
  - Add a temperature-relevant signal (for example, delta-Tm style models when available) and report mismatch risk.

Primary source:
- https://pubmed.ncbi.nlm.nih.gov/39864358/

### E) Data quality and calibration sets are now strong enough to enforce in-workflow controls

- Curated mutation databases continue to expand and support method calibration/triage.
- Practical implication:
  - Calibrate thresholds on known stabilizing/neutral/destabilizing mutations in the same scaffold family before applying fixed cutoffs.

Primary source:
- https://pubmed.ncbi.nlm.nih.gov/40665772/

## Supplemental benchmarking context

- Broad structure-model benchmark context:
  - https://www.nature.com/articles/s43588-024-00719-w

Use this as context for model quality variability, not as a direct DDG benchmark.
