# Use-case Playbook

Select the smallest workflow that fits the request.

## 1) Thermostability Engineering

Goal:
- Improve fold robustness with minimal functional disruption.

Default workflow:

1. Define constraints (active site, interfaces, disulfides).
2. Run candidate-site discovery and rank by structural context/risk.
3. Prioritize second-shell, loop-rigidifying, and packing candidates.
4. Generate focused single-site and low-order combinations.
5. Score with at least two methods and rank by consensus.
6. Escalate only top hits to orthogonal re-scoring.
7. Add a temperature-oriented signal when available (for example, delta-Tm style model) before final lead selection.

Watchouts:
- False positives from overpacked cores.
- Additivity assumptions for multi-site variants.

## 2) Saturation at a Single Position

Goal:
- Triage all 19 non-WT substitutions at one residue.

Default workflow:

1. Validate WT residue identity at the target position.
2. Generate all alternatives at the site.
3. Run fast first-pass scoring.
4. Group into stabilizing / near-neutral / destabilizing bands.
5. Re-score top and boundary variants with a second method.

Watchouts:
- Numbering mismatch between sequence and structure.
- Over-interpretation of small score gaps.

## 3) Sequence-only Requests

Goal:
- Provide a defensible path when no experimental structure exists.

Default workflow:

1. Build WT and mutant models under consistent AF settings.
2. Inspect local confidence near mutation sites.
3. Use AI outputs as structural plausibility evidence only.
4. Rank with DDG or learned stability predictors, not pLDDT alone.
5. Report assumptions and uncertainty explicitly.

Watchouts:
- Using pLDDT as a direct stability proxy.
- Ignoring local geometry around mutated residues.

## 4) Clinical or Mechanistic Variant Interpretation

Goal:
- Explain stability impact with functional-risk framing.

Default workflow:

1. Map variant to structure and functional neighborhood.
2. Compute stability estimates with at least two methods.
3. Integrate conservation and structural context.
4. Separate stability signal from functional-essentiality signal.
5. Recommend confirmatory experiments before strong claims.

Watchouts:
- Conflating destabilization with pathogenicity certainty.
- Ignoring literature or database context when available.

## 5) Interface/Assembly-Sensitive Engineering

Goal:
- Improve robustness without damaging oligomerization or partner binding.

Default workflow:

1. Lock biological assembly and interface residues before mutagenesis.
2. Use interface-aware scoring in addition to monomer stability tools.
3. Flag candidates that alter buried interface polar networks or key salt bridges.
4. Re-score top interface variants with an orthogonal method.
5. Keep lead and mechanistic-control variants explicitly separated.

Watchouts:
- Using monomer-only DDG tools as the sole decision basis for interface edits.
- Ignoring assembly-state mismatch between in silico setup and assay format.
