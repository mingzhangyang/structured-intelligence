---
name: design-thermostable-mutations
description: Decision-grade enzyme/protein mutation design for thermostability with bioactivity-preserving constraints enforced by default, plus structure-aware and consensus-ranking workflows.
---

# Skill: Design Thermostable Mutations

## Use When
Use this skill when users need mutation design or triage for proteins/enzymes and care about both:
- improved thermostability/heat tolerance
- preserved catalytic activity/bioactivity

Typical requests:
- "Which positions should I mutate first?"
- "Design a stability-focused mutation library without breaking active site chemistry"
- "Rank these candidate mutations by stability evidence"
- "Build a decision-grade shortlist for wet-lab validation"
- "Predict the stability impact of a specific variant (e.g., a clinical or engineered substitution)"

## Decision-Grade Guardrails (Default)
These are enforced by default unless explicitly overridden:
1. Bioactivity constraints must be supplied for design decisions:
   - active-site/catalytic/cofactor/disulfide/blocklist positions
2. Functional/protected positions are blocked from routine mutagenesis.
3. Non-conservative substitutions are rejected in conservative mode.
4. User-facing mutation notation is 1-based and WT residue-validated.

## Inputs
- Required:
  - WT sequence (`--sequence` or `--fasta`)
- Required for decision-grade design mode:
  - functional constraints (at least one: active/cofactor/disulfide/blocklist)
- Optional:
  - structure (`.pdb`/`.cif`/`.mmcif`)
  - mutation candidates (`A123V` format)
  - assay context (pH, temperature, ligand/cofactor state)

## Workflow
Choose the smallest workflow that still supports decision-grade confidence.

### Path A: Fast Heuristic Design (single-script)
Use when structure and external predictors are unavailable.

Script:
- `scripts/design_thermostable_mutations.py`

Capabilities:
- strict sequence/mutation validation
- protected-residue enforcement (default)
- conservative-substitution enforcement (default)
- heuristic DDG + local aggregation-risk filtering
- ranked candidate output with rejection reasons

### Path B: Structure-Aware Consensus (recommended)
Use when structure is available and shortlist quality matters.

0. One-command orchestrator (recommended entrypoint):
- `scripts/run_decision_pipeline.py`

1. Discover candidate sites with structural context and functional guardrails:
- `scripts/discover_candidate_sites.py`

2. Generate focused single/multi-site library:
- `scripts/generate_mutation_library.py`

3. Resolve sequence-to-structure numbering safely:
- `scripts/structure_residue_mapper.py`

4. Run structure-based scoring (FoldX wrappers):
- `scripts/run_foldx_batch.py`
- `scripts/run_foldx_chunked.py` (large libraries)

5. Aggregate multiple metrics with direction-aware consensus:
- `scripts/consensus_stability_rank.py`

6. Produce decision-ready report using:
- ranked consensus
- support fraction across tools
- functional risk flags
- assumptions and escalation notes

7. Optional AI-assisted route for structure generation/summary:
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

By default, the pipeline:
- requires functional constraints for decision-grade discovery
- blocks protected sites during library generation
- auto-derives protected sites from active/cofactor/disulfide/blocklist when not explicitly set

## Output Contract
Always include:
1. Baseline stability summary
2. Functional-constraint enforcement status
3. Ranked candidates with rationale
4. Rejection summary (rule-level counts)
5. Functional risk flags (active/cofactor/disulfide/interface/conservation)
6. Confidence and escalation section

For consensus workflows, also include:
- per-tool metric table
- consensus score and support fraction
- metric directionality and normalization choices

## References
- `references/mutation-design-workflow.md`
- `references/mutation-design-principles.md`
- `references/stability-prediction-playbook.md`
- `references/use-case-playbook.md`
- `references/report-template.md`
- `references/troubleshooting.md`
- `references/literature-evidence-2022-2026.md`

## Evaluation and Bundle Checks (Optional)
- `evals.json`
- `scripts/run_skill_evals.py`
- `scripts/validate_skill_bundle.py`

## Install
From repository root:

```bash
# Codex (default)
./scripts/install_skill.sh design-thermostable-mutations

# Claude Code
./scripts/install_skill.sh design-thermostable-mutations --tool claude

# Other tools
./scripts/install_skill.sh design-thermostable-mutations --dest ~/.my-tool/skills
```

## Limits
- Heuristic scores are triage evidence, not biochemical truth.
- Predictions must be experimentally validated (Tm/T50/activity).
- If functional constraints are incomplete, activity-preservation confidence drops.
- Common failure cases:
  - structure numbering mismatches that are not validated before scoring
  - incomplete active-site/cofactor/disulfide/blocklist constraints
  - overlarge mutation libraries that exceed practical scoring budgets
