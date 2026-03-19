---
name: predict-protein-heat-stability
description: Decision-grade protein thermal stability prediction (Tm, thermophilicity, ΔTm) from sequence and/or structure, with multi-tool evidence integration and calibrated interpretation.
---

# Skill: Predict Protein Heat Stability

## Use When
Use this skill when users need to assess the thermal stability of a protein or compare variant heat stability:
- "Is this protein thermostable?"
- "What is the predicted Tm of this enzyme?"
- "How does this mutation affect heat stability?"
- "Which of these variants is most thermostable?"
- "Will this enzyme be stable at 60°C?"
- "Estimate the melting temperature of this sequence"
- "Compare the thermostability of these two protein variants"

## Inputs
- Required:
  - Protein sequence (`--sequence` or `--fasta`)
- Optional:
  - Structure file (`.pdb`/`.cif`/`.mmcif`)
  - Mutation list (`A123V` format, one per line or comma-separated)
  - Organism optimal growth temperature (OGT) for context
  - Target operating temperature (e.g., for industrial applications)
  - Functional constraints (active-site, cofactor positions) for risk-aware output

## Workflow
Choose the smallest workflow that still supports decision-grade confidence.

### Path A: Sequence-Only Assessment
Use when no structure is available.

Script:
- `scripts/predict_heat_stability.py`

Capabilities:
- sequence validation (alphabet, length, ambiguous residues)
- composition-based features: GRAVY index, charged residue ratio (Arg+Lys+Asp+Glu), aromatic content (Trp+Tyr+Phe), instability index (Guruprasad et al.)
- salt bridge potential (Arg+Lys vs Asp+Glu charge balance)
- predicted thermophilicity class from feature thresholds (calibrated on known thermophile/mesophile datasets)
- confidence band with calibration caveats
- homolog-guided OGT estimate (if WebSearch available)

Example:
```bash
python3 scripts/predict_heat_stability.py \
  --fasta wt.fasta \
  --output stability_report.json
```

### Path B: Structure-Aware Prediction
Use when a structure is available or can be generated (AlphaFold/ColabFold).

Steps:
1. Validate structure (chain selection, residue completeness, numbering match to FASTA).
2. Repair structure with `FoldX RepairPDB` before scoring.
3. Run `FoldX Stability` to estimate ΔG of folding.
4. Optionally run HoTMuSiC or MAESTRO for Tm-scale estimates.
5. Cross-validate with sequence-based features from Path A.
6. Report consensus with per-tool table.

Practical guidance:
- Fix chain and protonation state before comparing WT vs. mutant runs.
- Run WT as a control to anchor relative ΔΔG calculations.
- Do not treat FoldX ΔG absolute values as Tm; use Tm-oriented tools for direct Tm estimates.

### Path C: Variant ΔTm Prediction
Use when comparing WT vs. specific mutants for thermostability rank-ordering.

Steps:
1. Validate all mutation notation (1-based, WT residue must match sequence).
2. If structure available, build mutant models with `FoldX BuildModel`.
3. Score each variant with at least two independent tools.
4. Rank by consensus ΔΔG/ΔTm evidence.
5. Flag variants that overlap functional constraints if provided.

Example (with structure):
```bash
python3 scripts/predict_heat_stability.py \
  --fasta wt.fasta \
  --structure model.pdb \
  --mutations A123V,G45S,T210I \
  --active-site 57,102,195 \
  --output variant_stability_report.json
```

## Output Contract
Always include:
1. Predicted thermostability class (hyperthermophilic/thermophilic/mesophilic/thermolabile) with confidence band
2. Key supporting features table (GRAVY, charged ratio, aromatic content, instability index)
3. Predicted Tm range if structure-based tools were run (with ±error caveat)
4. Per-variant ΔΔG/ΔTm table (if mutations provided)
5. Functional risk flags (if constraints provided)
6. Interpretation limits and escalation notes

## Interpretation Bands

### Thermostability Class (Approximate Tm Ranges)
| Class | Typical Tm | Typical OGT |
|---|---|---|
| Hyperthermophilic | > 80°C | > 80°C |
| Thermophilic | 60–80°C | 50–80°C |
| Mesophilic | 40–60°C | 20–50°C |
| Thermolabile/Psychrophilic | < 40°C | < 20°C |

These bands are approximate; protein family and domain architecture affect calibration.

### Sequence Feature Thresholds (Heuristic)
- GRAVY index > 0: net hydrophobic (not a direct thermostability predictor, context-dependent)
- Instability index < 40: likely stable in vitro; ≥ 40: potentially unstable
- Charged residue ratio (RKED/all) > 0.15 and Arg/(Arg+Lys) > 0.5: thermophile-associated pattern
- Aromatic content (WYF) > 0.06: elevated aromatic packing, common in thermophiles

### ΔΔG Effect Sizes (Typical, Tool-Dependent)
- |ΔΔG| > 1.0 kcal/mol: strong effect candidate
- |ΔΔG| 0.3–1.0 kcal/mol: moderate effect
- |ΔΔG| < 0.3 kcal/mol: near-neutral/uncertain

Always verify sign convention per tool (negative = stabilizing in FoldX; varies in others).

## References
- `references/heat-stability-prediction-playbook.md`

## Install
From repository root:

```bash
# Claude Code
./scripts/install_skill.sh predict-protein-heat-stability --tool claude

# Codex (default)
./scripts/install_skill.sh predict-protein-heat-stability

# Custom destination
./scripts/install_skill.sh predict-protein-heat-stability --dest ~/.my-tool/skills
```

## Limits
- Sequence-only predictions are low-resolution; structural analysis is strongly preferred for final decisions.
- Tm predictions carry ±5–10°C typical error for most tools; treat as triage evidence, not ground truth.
- Heuristic composition features are calibrated on soluble globular proteins; multi-domain, membrane, and intrinsically disordered proteins require special handling.
- Tool calibration may not transfer across distant protein families.
- Stabilizing variants are systematically under-predicted by current DDG tools; treat stabilizing predictions as high-uncertainty until orthogonally validated.
- All predictions require experimental validation (DSF, DSC, thermal shift assay, Tm determination).
- Common failure cases:
  - mutation indexing mismatches between sequence and structure numbering
  - model-quality artifacts from low-confidence structure regions
  - incompatible DDG sign conventions when comparing outputs across tools
