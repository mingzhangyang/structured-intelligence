# Mutation Design Principles for Enzyme Stability

## 1) Define Objective and Constraints First

Before proposing mutations, explicitly capture:
- Stability objective: global fold stability, thermal tolerance, storage robustness, solvent resistance, or pH tolerance
- Functional constraints: catalytic residues, substrate channel geometry, cofactor contacts
- Experimental context: pH, ionic strength, ligand state, oligomerization state

Avoid optimizing stability in isolation when catalytic turnover must be preserved.

## 2) Build a Residue Risk Map Before Suggesting Sites

Use three bins:
- Blocklist (default no-mutate): catalytic residues, catalytic first-shell contacts, direct metal ligands, native disulfide residues, covalent cofactor anchors
- Caution: interface hotspots, channel gates, conserved gly/pro hinges, highly conserved buried residues
- Designable: second-shell positions, loop-rigidification targets, helix-caps, packing-defect or solvent charge-network positions

Only mutate blocklist/caution positions when the user explicitly asks for mechanistic perturbation.

## 3) Prioritize Sites with Structural Rationale

Prefer positions with interpretable stabilization mechanisms:
- Core packing defects: cavities or loosely packed hydrophobic cores
- Helix termini: N-cap and C-cap residues that can improve local hydrogen bonding
- Flexible loops: high B-factor or high RMSF regions that tolerate rigidifying substitutions
- Surface charge networks: potential salt-bridge completion in solvent-exposed regions

Operationalize this with `scripts/discover_candidate_sites.py` when structure is available:
- Rank positions with exposure/flexibility/active-shell context.
- Emit explicit risk tags and block reasons.
- Export site specs for downstream library generation.

Use caution at:
- Active-site first shell
- Glycine-rich motifs or hinges
- Disulfide-forming cysteines
- Multimer interfaces with uncertain assembly state

## 4) Design Single-site Libraries

Use focused substitutions, not full 19-aa saturation by default.

Common focused sets:
- Core hydrophobic tuning: `AILVFMWY`
- Loop rigidification: `P` (context-dependent), `G -> A`
- Helix propensity tuning: `A`, `L`, occasionally `E`
- Charge engineering: `D/E/K/R` with local electrostatics checks

Require WT residue validation for every notation (`A123V` means residue 123 is `A` in WT).

Site-level biochemical guardrails:
- Avoid burying new formal charge unless a compensating H-bond/salt-bridge partner is nearby.
- Treat `G -> P` as high-risk in beta-strands or tight turns unless geometry is inspected.
- Treat `X -> C` with caution unless disulfide feasibility is explicitly evaluated.

## 5) Design Multi-site Libraries Carefully

For multi-site combinations:
- Combine mutations with non-overlapping structural mechanisms
- Limit combinatorial order initially (`k <= 2` or `k <= 3`)
- Exclude combinations with obvious steric conflict or charge overcompensation
- Avoid stacking multiple core-bulking substitutions in one local cluster without orthogonal checks

Non-additivity is expected. Treat pair/triple predictions as hypotheses until independently re-scored.

## 6) Sequence and Evolution Filters

When MSA data are available:
- Preserve highly conserved catalytic positions
- Prefer substitutions observed among homologs at moderate frequency
- Penalize rare replacements in buried, conserved cores

Representative MSA and sequence-based scoring tools:
- EVMutation: evolutionary coupling model; scores variants by epistatic log-ratio
- ESM-1v: protein language model; log-likelihood of variant vs. WT as a fitness/stability proxy
- GEMME: global epistatic model; fast conservation-aware variant ranking without explicit MSA alignment

Use these as pre-filters before expensive structure-based scoring, not as standalone decision tools.
Combine conservation with structure, not as a single decision criterion.

## 7) Minimum Reporting Standard

For each proposed mutant, report:
- Mutation code(s)
- Structural context (core/surface/loop/active-site distance)
- Rationale tag (packing, electrostatics, rigidity, etc.)
- Predicted stability evidence sources
- Functional risk flag
- Assumption block (assembly, protonation, ligand/cofactor state, pH/temperature)
