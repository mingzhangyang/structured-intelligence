# Troubleshooting and Failure Modes

Use this checklist when predictions look inconsistent or implausible.

## 1) Mapping and Input Integrity

- Confirm every mutation notation against WT sequence identity.
- Resolve FASTA-to-structure numbering mismatches before DDG scoring.
- Verify chain selection and residue insertion code handling.

Common symptom:
- Large DDG swings for many variants at once.

Likely causes:
- Wrong chain, off-by-one mapping, or mismatched WT residue.

## 2) Structure Quality and Context

- Prefer experimentally resolved structures when available.
- For predicted models, check confidence near mutation sites.
- Ensure cofactors, ligands, ions, and disulfides are represented consistently.

Common symptom:
- Mutations near active/cofactor sites look strongly stabilizing but conflict with mechanism.

Likely causes:
- Missing ligand/cofactor context or incorrect protonation assumptions.

## 3) Metric Interpretation Errors

- Confirm sign conventions per tool before aggregation.
- Do not rank by pLDDT alone.
- Treat small score differences as uncertain unless replicated.

Common symptom:
- Opposite conclusions from different tools.

Likely causes:
- Mixed metric directionality, scale mismatch, or single-run noise.

## 4) Multi-mutation Overconfidence

- Treat additive multi-site gains as hypotheses.
- Re-score top multi-site hits with an orthogonal method.
- Flag epistasis risk explicitly.

Common symptom:
- Very large predicted stabilization for high-order combinations.

Likely causes:
- Overpacking artifacts or non-additive effects not modeled reliably.

## 5) Experimental Condition Drift

- Record pH, ionic strength, temperature, and oligomer state assumptions.
- Keep WT and mutant setup conditions identical across tools.

Common symptom:
- In silico ranking fails to match wet-lab directionality.

Likely causes:
- Tool setup not aligned with assay conditions.

## Minimum Recovery Procedure

If outputs are suspicious, rerun in this order:

1. Re-validate mutation mapping and WT identity.
2. Recompute WT control and a known reference mutation.
3. Re-score top candidates with a second method.
4. Re-rank with explicit metric directions and support fractions.
