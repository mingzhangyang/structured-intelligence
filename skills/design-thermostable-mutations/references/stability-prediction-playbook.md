# Stability Prediction Playbook (Classical + AI-Assisted)

## 1) Core Principle

Treat stability prediction as evidence integration, not single-model truth.
Use at least two independent predictors when possible.

## 2) Tool Classes

### Structure-based DDG estimators

- FoldX `BuildModel`: fast and practical for large variant sets
- Rosetta `cartesian_ddg`: slower, often useful as an orthogonal score
- DynaMut2 / DUET / SDM: complementary web/local estimators

Practical guidance:
- Verify the sign convention for each tool before comparing values
- Run WT controls and replicate runs for noisy tools
- Keep protonation and ligand state consistent across WT and mutants
- Keep biological assembly/chain choice fixed across WT and mutants

### Sequence-based or learned stability models

- Useful when no reliable structure is available
- Good as prefiltering layers before expensive structure-based scoring
- Should not replace structural review for top candidates

Representative tools:
- EVMutation: evolutionary coupling-based variant effect predictor
- ESM-1v: protein language model variant log-likelihood scoring
- GEMME: global epistatic model leveraging sequence conservation

### Temperature-oriented Tm predictors

Use these when thermostability (not generic fold stability) is the explicit objective.
These complement DDG tools with direct ΔTm-scale evidence.

Representative tools:
- HoTMuSiC: structure-based ΔTm predictor; directly models melting temperature change
- MAESTRO: energy-based stability predictor with Tm change output
- ThermoNet: CNN-based ΔΔG/ΔTm predictor trained on experimental stability data

Practical guidance:
- Prefer at least one Tm-oriented signal alongside DDG scores when ranking for thermostability.
- Do not substitute Tm predictors for DDG tools; use them as a second axis in consensus ranking.
- Calibrate Tm predictor thresholds on known protein variants in the same temperature range.

## 3) AlphaFold and ColabFold Usage

Use AlphaFold outputs to support structural plausibility, not to directly infer DDG.

Recommended process:
1. Generate WT and mutant models under the same AF pipeline settings.
2. Compare local confidence around mutation sites (not only global pLDDT).
3. Inspect changes in packing, hydrogen-bond opportunities, and clashes.
4. Feed structures into DDG tools or additional learned stability predictors.

Do not do this:
- Rank candidates by pLDDT alone.
- Interpret small pLDDT differences as quantitative DDG.

## 4) Consensus Ranking Strategy

Suggested approach:
1. Collect metrics in one table (`tool_scores.csv`).
2. Normalize each metric with correct directionality.
3. Prefer rank normalization for outlier robustness when tool scales differ strongly.
4. Average with explicit weights.
5. Track support count and support fraction.

Use `scripts/consensus_stability_rank.py` for this aggregation.

## 5) Interpretation Bands (Typical, Not Universal)

For DDG-like metrics where negative implies stabilizing:
- `< -1.0`: strong stabilizing candidate
- `-1.0 to -0.3`: likely stabilizing
- `-0.3 to 0.3`: near-neutral/uncertain
- `> 0.3`: potentially destabilizing

Always adapt thresholds to tool calibration and enzyme system.

## 6) Failure Modes and Checks

Common failure modes:
- Wrong chain selection
- Residue numbering mismatch between FASTA and structure
- Missing cofactors/ions that alter local geometry
- Artifactually favorable predictions for overpacked cores

Checks to enforce:
- Validate mutation mapping before scoring
- Re-score top hits with an orthogonal method
- Flag high-risk functional neighborhoods for experimental triage
- Downgrade confidence when large gains are predicted only for high-order multi-mutation designs

## 7) Recent Benchmark Signals (2024-2025)

Use these as practical guardrails for interpretation:
- AF3 benchmarking reports strong local structural improvements but limited global gains in some monomer settings; do not assume AF3 always outperforms AF2/ColabFold for every stability workflow.
- Large-scale evaluation of complex-mutation DDG predictors reports strong destabilizing-class bias and weak recall for stabilizing variants; treat stabilizing predictions as high-uncertainty until orthogonally validated.
- Integrative workflows that combine DDG with temperature-oriented signals (for example, delta-Tm style models) are increasingly favored over single-score ranking when thermostability is the objective.
- Recent practical guides emphasize choosing tools by specific engineering objective (thermostability, pH tolerance, solvent resistance, kinetics tradeoff), not by one universal leaderboard.
