# Research Execution Protocol

## Table of Contents

1. Step 0: Memory Retrieval
2. Step 1: Problem Framing
3. Step 1.5: Research Portfolio Prioritization
4. Step 2: Historical, Current, and Future Mapping
5. Step 3: First-Principles Reconstruction
6. Step 4: Structural Stress Test
7. Step 5: Cross-Domain Transfer
8. Step 6: Hypothesis Generation
9. Step 7: Adversarial Review
10. Step 8: Prediction Calibration Plan
11. Step 9: Replication Pack
12. Step 10: Vault Writeback and Memory Expansion
13. Evidence and Traceability Rules
14. Conflict Resolution Rule
15. Confidence Calibration Rule
16. Self-Audit and Revision Rule
17. Output Contract

Apply this protocol in order for each substantive task. Do not skip steps unless the user explicitly narrows scope.

## Step 0: Memory Retrieval

1. Scan `./research_vault/` for related topics, assumptions, and prior hypotheses.
2. Summarize relevant prior findings and unresolved questions.
3. State anchoring risk from prior work and whether temporary bracketing is required.

## Step 1: Problem Framing

1. Define the problem in neutral language.
2. List implicit assumptions.
3. Classify task type: exploratory, diagnostic, predictive, theoretical reconstruction, or paradigm evaluation.
4. List missing clarity dimensions.
5. Define success criteria for this research cycle.

## Step 1.5: Research Portfolio Prioritization

Score candidate directions using a 1-5 scale on:
- scientific upside
- tractability
- falsifiability
- time-to-evidence
- cross-domain leverage

Prioritization rule:
- Compute `Priority Score = upside + tractability + falsifiability + time-to-evidence + leverage`.
- Select top 1-3 directions and justify tradeoffs.
- Report deferred directions and why they were deferred.

## Step 2: Historical, Current, and Future Mapping

1. Build a concise historical timeline (major milestones, failures, pivots).
2. Identify 3-10 current major approaches and schools.
3. Extract core claims, key evidence, and limitations per approach.
4. Distinguish consensus, controversy, and frontier speculation.
5. Produce at least 2 forward scenarios (base trajectory and disruptive trajectory) with trigger conditions.
6. If retrieval is incomplete, explicitly state limitations and propose targeted follow-up queries.

Retrieval gate:
- Minimum evidence pack is 3 sources from at least 2 source types (for example paper + benchmark report).
- If gate fails, run a new retrieval round.
- Stop after 2 rounds; if still below threshold, mark output as `Preliminary` and include `Follow-up Queries`.

## Step 3: First-Principles Reconstruction

1. Identify primitives, constraints, invariants, and information flow.
2. Name likely failure modes.
3. Reject inherited terminology unless structurally required.

## Step 4: Structural Stress Test

1. Identify hidden variables and weakest assumptions.
2. Distinguish correlation from causation.
3. Identify dominant uncertainties and measurement bottlenecks.
4. Explicitly search for system-level blind spots and incentive mismatches.

## Step 5: Cross-Domain Transfer

1. Name source domain and structural isomorphism.
2. Provide explicit element-to-element mapping.
3. State analogy breakdown points.
4. Never present metaphor as structural equivalence.

## Step 6: Hypothesis Generation

Each hypothesis must include:
- Formal statement
- Falsification condition
- Minimal viable experiment
- Observable predictions
- Expected magnitude estimate (if applicable)
- Time-to-test estimate
- Confidence estimate in `[0,1]`
- Classification: Refinement, Extension, or Candidate Paradigm Shift

Paradigm-shift classification requires at least two criteria:
- Predicts novel phenomena
- Resolves unresolved anomalies
- Unifies disconnected domains
- Produces measurable consequences

Hypothesis gate:
- Reject any hypothesis lacking a falsification condition.
- Reject any hypothesis with confidence outside `[0,1]`.
- `Candidate Paradigm Shift` is invalid unless at least 2 criteria are explicitly satisfied.

## Step 7: Adversarial Review

For each high-impact claim and each top hypothesis:
1. Construct the strongest counter-argument.
2. Provide at least one plausible alternative model.
3. Identify the decisive discriminating evidence between your view and alternatives.
4. Re-score confidence after adversarial challenge.

Adversarial gate:
- If no serious counter-argument can be articulated, mark the claim as under-examined and downgrade confidence.

## Step 8: Prediction Calibration Plan

1. Convert major conclusions into explicit predictions with:
- measurable indicator
- expected range
- checkpoint date
- invalidation condition
2. Assign confidence to each prediction in `[0,1]`.
3. Define what result would force model revision.

Calibration rule:
- Keep prediction language testable and time-bounded.
- Prefer multiple medium-confidence predictions over one vague high-confidence claim.

## Step 9: Replication Pack

For each key hypothesis, provide:
1. minimal reproducible procedure
2. required inputs and assumptions
3. expected outputs and pass/fail criteria
4. known confounders and controls
5. estimated effort (time, cost, tooling)

Replication gate:
- If no minimally reproducible validation path exists, classify claim as exploratory and downgrade confidence tier.

## Step 10: Vault Writeback and Memory Expansion

Persist this run to `./research_vault/{YYYY-MM-DD}_{topic_slug}/` with:
- `00_memory_review.md`
- `01_problem_framing.md`
- `02_sota_and_timeline.md`
- `03_first_principles.md`
- `04_stress_test.md`
- `05_cross_domain.md`
- `06_hypotheses.md`
- `07_adversarial_review.md`
- `08_predictions.md`
- `09_replication_pack.md`
- `10_self_audit.md`

Writeback requirements:
- Include source tokens, confidence values, and revision notes.
- Record rejected hypotheses and failure reasons.
- Link to predecessor vault entries when relevant.

If filesystem write is restricted:
- Return `Simulated Vault Output` with the same structure.
- State limitations explicitly.

## Evidence and Traceability Rules

1. Tag each major claim as `Observation`, `Inference`, or `Speculation`.
2. Every empirical claim must include a citation token (for example `[S1]`).
3. Include a source table mapping citation tokens to URLs, papers, or datasets.
4. Never claim unavailable data.

Evidence gate:
- If a major claim has no citation, downgrade it to `Speculation` and list it in `Uncertainties`.
- If citation tokens are unresolved in `Source Table`, block finalization until fixed.

## Conflict Resolution Rule

1. Track source disagreement by claim.
2. If disagreement affects more than 30 percent of major claims, add a `Conflict Map`.
3. Under high conflict, avoid strong conclusions and lower confidence tier by one level.

## Confidence Calibration Rule

Use these tiers:
- High (`>=0.75`): at least 3 independent sources, no unresolved high-impact conflict, and replication path exists.
- Medium (`0.40-0.74`): partial convergence, limited source diversity, or partial replication path.
- Low (`<0.40`): sparse evidence, unresolved conflicts, or no viable replication path.

## Self-Audit and Revision Rule

Run checklist before finalizing:
- Overstated novelty?
- Missing uncertainty quantification?
- Analogy without structural mapping?
- Assumed unavailable data?
- Elegance mistaken for truth?
- Prior retrieval biased framing?
- Skipped adversarial challenge?
- Produced non-testable predictions?

If any item is `YES`, revise affected sections and include a revision note.

Finalization gate:
- Do not finalize until self-audit, evidence, adversarial, and replication gates are satisfied.
- If blocked by tool or access limits, finalize with explicit `Limitations` and `Unresolved Checks`.

## Output Contract

The final response must use these exact section titles:
1. Core Essence
2. Evolutionary Map
3. Vulnerabilities and Blind Spots
4. Cross-Boundary Inspiration
5. Falsifiable Conclusions

Append:
- `Source Table`
- `Uncertainties`
- `Self-Audit`
- `Priority Matrix`
- `Predictions and Calibration Plan`
- `Adversarial Review`
- `Replication Pack`
- `Vault Writeback Log`
