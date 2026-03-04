# Mutation Stability Report Template

Use this structure for consistent decision-ready outputs.

## 1) Job Summary

- Target protein:
- Input type: FASTA only / FASTA + structure
- Structure source and chain:
- Objective: stability / thermostability / mixed objective
- Mutation scope: single-site / focused combinatorial / saturation

## 2) Methods and Assumptions

- Numbering and mapping method:
- Toolchain used:
- Metric directions (higher-is-better declarations):
- Environmental assumptions: pH, ligand/cofactor state, oligomer state
- Protonation assumptions near catalytic residues:
- Structure context lock: apo vs holo, metal occupancy, assembly model

## 3) Candidate Table

Required columns:

- `mutations`
- `structural_context`
- `tool_scores`
- `consensus_rank`
- `support_count`
- `support_fraction`
- `functional_risk_flag`
- `risk_class` (lead / caution / mechanistic-control)
- `notes`

If site discovery was performed first, include a site-level pre-table with:
- `seq_pos`
- `candidate_score`
- `active_shell`
- `exposure_class`
- `risk_tags`
- `site_spec`

## 4) Confidence Bands

Use support fraction bands for quick triage:

- High confidence: `> 0.75`
- Medium confidence: `0.50 - 0.75`
- Low confidence: `< 0.50`

These bands are heuristics and should be interpreted with tool calibration in mind.

## 5) Functional Risk Summary

Explicitly flag candidates touching:

- Active site first shell
- Cofactor/ligand contacts
- Disulfide positions
- Oligomer interface
- Metal coordination shell
- Conserved gly/pro hinges

## 6) Recommended Next Actions

- Shortlist for first-pass validation:
- Orthogonal re-scoring plan:
- Suggested controls:
- Experimental readouts:
- Any candidates excluded from lead set and why:

## Example Narrative Block

"Top candidates were prioritized by consensus rank across FoldX and Rosetta DDG
with explicit direction handling. Variants near catalytic residues were retained
only as mechanistic controls and not as stabilization leads."
