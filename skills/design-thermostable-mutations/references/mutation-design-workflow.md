# Decision-Grade Thermostability Mutation Design Workflow

## Goal
Design mutation sites that improve thermostability while preserving enzyme/protein bioactivity.

## Default Safety Policy (Enforced)
1. Functional constraints are required for decision-grade design:
   - active-site and/or catalytic positions
   - cofactor/metal-contact positions
   - disulfide positions
   - explicit user blocklist positions
2. Mutations at protected positions are forbidden by default.
3. Non-conservative substitutions are rejected by default.

## Path A: Fast Heuristic Design
Use when structure and external scorers are unavailable.

Script:
- `scripts/design_thermostable_mutations.py`

Core outputs:
- baseline stability profile
- protected-site enforcement summary
- ranked candidates
- rule-level rejection summary

## Path B: Structure-Aware Consensus Design (Recommended)
0. One-command pipeline:
- `scripts/run_decision_pipeline.py`
1. Site discovery with constraints:
- `scripts/discover_candidate_sites.py`
2. Library generation:
- `scripts/generate_mutation_library.py`
3. Sequence-to-structure mapping:
- `scripts/structure_residue_mapper.py`
4. FoldX batch scoring:
- `scripts/run_foldx_batch.py`
- `scripts/run_foldx_chunked.py` (large runs)
5. Multi-metric aggregation:
- `scripts/consensus_stability_rank.py`
6. Optional AlphaFold/ColabFold batch support:
- `scripts/run_colabfold_batch.py`

Example:
```bash
python3 scripts/run_decision_pipeline.py \
  --sequence-fasta wt.fasta \
  --structure model.pdb \
  --active-site 57,102,195 \
  --cofactor-sites 64,66 \
  --blocklist-sites 1-5 \
  --run-foldx \
  --run-consensus
```

Default pipeline guardrails:
1. Discovery requires functional constraints unless explicitly overridden.
2. Library generation requires protected sites unless explicitly overridden.
3. If protected sites are not supplied, they are auto-derived from active/cofactor/disulfide/blocklist constraints.

## Candidate Filtering Rules
A candidate mutation should pass all:
1. Not at protected positions
2. DDG <= minimum stabilizing threshold (default `-0.3`)
3. Aggregation-risk delta <= max aggregation delta (default `0`)
4. Conservative substitution (unless explicitly overridden)

## Confidence and Escalation
- Treat predictions as ranked hypotheses, not biochemical truth.
- For high-stakes decisions, use orthogonal methods (FoldX/Rosetta/ML consensus).
- Confirm experimentally with Tm/T50/activity assays.

## Coordinate Convention
Use 1-based positions in all user-facing outputs.
