---
name: stat-bayesian-estimation
description: Estimate model parameters using Bayesian inference (MCMC via Stan or PyMC), returning posterior distributions and credible intervals.
---

# Skill: Bayesian Parameter Estimation

## Use When

- User wants to estimate parameters with full uncertainty quantification via posterior distributions
- User wants to incorporate prior knowledge about parameters
- User needs credible intervals instead of frequentist confidence intervals
- Use cases: dose-response modeling, population parameter estimation, hierarchical biological models

## Inputs

- Required:
  - Data table (CSV or TSV) with observed values
  - Model specification: response variable, predictor variables, model family (`normal`, `poisson`, `binomial`)
- Optional:
  - Prior distributions for each parameter (default: weakly informative priors — normal(0, 10) for coefficients)
  - Number of MCMC chains (default: `4`)
  - Number of samples per chain (default: `2000`, warmup: `1000`)
  - Target acceptance rate (default: `0.8`)
  - Backend: `pymc` (default) or `stan`
  - Output directory (default: `./bayes_output`)

## Workflow

1. Read data; validate response and predictor columns.
2. Set up Bayesian model with specified family and prior distributions.
3. Run MCMC sampling with the specified backend (PyMC or Stan).
4. Check convergence: R-hat statistic (should be < 1.01 for all parameters), effective sample size (ESS > 400).
5. Extract posterior samples; compute posterior mean, median, standard deviation, and 94% credible interval (HDI) for each parameter.
6. Generate trace plots (one per parameter) to visually assess convergence.
7. Generate posterior distribution plots (one per parameter).
8. Generate posterior predictive check plot (observed vs. simulated data).
9. Write posterior summary (TSV), trace plots (PDF), and posterior plots (PDF) to output directory.
10. Report convergence diagnostics; flag any parameters with R-hat ≥ 1.01 or ESS < 400.

## Output Contract

- Posterior summary table (TSV): parameter, mean, sd, median, hdi_lower_94, hdi_upper_94, r_hat, ess_bulk, ess_tail
- Trace plots (PDF)
- Posterior distribution plots (PDF)
- Posterior predictive check plot (PDF)
- Convergence warnings (printed to stdout if any)

## Limits

- Requires PyMC or CmdStanPy to be installed; check environment before running.
- MCMC can be slow for complex models or large datasets; variational inference (ADVI) is faster but approximate.
- Weakly informative default priors may be inappropriate for constrained parameters (e.g., probabilities must be [0,1]) — specify priors explicitly when needed.
- R-hat ≥ 1.01 indicates non-convergence; increase warmup or reparameterize model.
- Common failure: identifiability issues (collinear predictors) causing MCMC to fail to mix.
