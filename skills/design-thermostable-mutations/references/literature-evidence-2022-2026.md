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
- Zheng et al., "Assessing computational tools for predicting protein stability changes upon missense mutations using a new dataset", Protein Science, 2024
- https://pubmed.ncbi.nlm.nih.gov/38084013/

### B) Additivity assumptions fail often for multi-mutation design

- Modern benchmarking confirms non-additivity/epistasis as a major failure point for naive multi-site scoring.
- Practical implication:
  - Restrict early combinatorial order.
  - Re-score top pairs/triples with orthogonal models.
  - Avoid direct arithmetic extrapolation from single-site DDG values.

Primary source:
- Dieckhaus et al., "Protein stability models fail to capture epistatic interactions of double point mutations", Protein Science, 2025
- https://pubmed.ncbi.nlm.nih.gov/39704075/

### C) AF3 improves local detail in many settings, but does not remove all global limitations

- Recent AF3 benchmarking highlights gains in local and interaction-relevant structure quality while showing mixed global improvements for some monomer tasks.
- Practical implication:
  - Use AF3/AF pipelines for structural plausibility and local inspection.
  - Do not infer stability ranking from AF confidence metrics alone.

Primary source:
- Peng et al., "A comprehensive benchmarking of the AlphaFold3 for predicting biomacromolecules and their interactions", Briefings in Bioinformatics, 2025
- https://pubmed.ncbi.nlm.nih.gov/41313605/

### D) Thermostability pipelines should integrate temperature-aware evidence

- Recent reviews emphasize integrating classical DDG signals with temperature-oriented predictors and assay-aware interpretation.
- Practical implication:
  - For thermostability objectives, avoid DDG-only ranking.
  - Add a temperature-relevant signal (for example, delta-Tm style models when available) and report mismatch risk.

Primary source:
- Peccati et al., "Computation of Protein Thermostability and Epistasis", WIREs Computational Molecular Science, 2025
- https://doi.org/10.1002/wcms.70045

### E) Data quality and calibration sets are now strong enough to enforce in-workflow controls

- Curated mutation databases continue to expand and support method calibration/triage.
- Practical implication:
  - Calibrate thresholds on known stabilizing/neutral/destabilizing mutations in the same scaffold family before applying fixed cutoffs.

Primary source:
- Musil et al., "FireProtDB 2.0: large-scale manually curated database of the protein stability data", Nucleic Acids Research, 2025
- https://pubmed.ncbi.nlm.nih.gov/41263104/

## Supplemental benchmarking context

- Broad structure-model benchmark context (geometric learning for stability prediction):
  - Xu et al., "Improving the prediction of protein stability changes upon mutations by geometric learning and a pre-training strategy", Nature Computational Science, 2024
  - https://pubmed.ncbi.nlm.nih.gov/39455825/

Use this as context for model quality variability, not as a direct DDG benchmark.
