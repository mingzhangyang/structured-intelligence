---
name: stat-learn-bayesian-network
description: Learn the structure and conditional probabilities of a Bayesian network from observational data for causal discovery or dependency modeling.
---

# Skill: Bayesian Network Learning

## Use When

- User wants to discover conditional dependencies and potential causal relationships among variables
- User wants to build a probabilistic graphical model for gene regulatory networks or clinical variable relationships
- User wants to perform probabilistic inference (e.g., what is the probability of disease given observed biomarkers)

## Inputs

- Required:
  - Data table (CSV or TSV): rows = observations, columns = variables (numeric or discrete)
- Optional:
  - Variable types per column: `continuous` or `discrete` (default: auto-detected)
  - Structure learning algorithm: `hc` (Hill-Climbing, default), `tabu` (Tabu search), or `pc` (PC algorithm, for large graphs)
  - Scoring function: `bic` (default), `aic`, or `bdeu` (for discrete data)
  - Whitelist of edges to force (CSV: from, to)
  - Blacklist of edges to forbid (CSV: from, to)
  - Number of bootstrap replicates for edge confidence (default: `100`)
  - Output directory (default: `./bn_output`)

## Workflow

1. Read data; detect or apply variable types; discretize continuous variables if needed for discrete BN learning (using quantile bins).
2. Learn network structure using the specified algorithm and scoring function.
3. Fit conditional probability distributions (CPDs) for each node given its parents.
4. Compute bootstrap confidence for each edge (fraction of bootstrap replicates containing that edge).
5. Report high-confidence edges (bootstrap support ≥ 0.8) vs. uncertain edges.
6. Visualize the learned DAG: nodes = variables, directed edges = learned dependencies, edge width proportional to bootstrap support.
7. Perform a Markov blanket analysis for each variable (its direct causes, effects, and spouses).
8. Write the DAG adjacency matrix (TSV), CPD parameters (TSV), network plot (PDF), and Markov blanket summary (TSV) to output directory.

## Output Contract

- DAG adjacency matrix (TSV): row = parent, column = child, value = bootstrap support (0–1)
- CPD table (TSV): node, parents, CPD parameters
- Network visualization (PDF): DAG with node labels and edge confidence
- Markov blanket summary (TSV): variable, parents, children, spouses
- High-confidence edge list (TSV): from, to, bootstrap_support

## Limits

- Structure learning is NP-hard; runtime grows exponentially with number of variables. Use PC algorithm for > 50 variables.
- Observational data cannot establish causality — learned edges represent statistical dependence, not necessarily causal direction.
- Requires sufficient sample size relative to number of variables (recommended: n > 5 × number of variables).
- Continuous variable discretization introduces information loss; consider Gaussian BN for purely continuous data.
- Common failure: cyclic structure detected during learning — enforce acyclicity via blacklisting or algorithm constraints.
