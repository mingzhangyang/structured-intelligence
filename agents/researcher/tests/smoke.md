# Smoke Test

## Scenario

Input topic: "What are the most plausible near-term bottlenecks in autonomous software engineering agents?"

## Expected

- Output includes the 5 required sections.
- Claims are tagged as observation, inference, or speculation.
- At least 2 falsifiable hypotheses are provided.
- Each hypothesis has a concrete falsification condition.
- Each hypothesis has a classification: Refinement, Extension, or Candidate Paradigm Shift.
- If any hypothesis is tagged Candidate Paradigm Shift, rationale includes at least 2 required criteria.
- Every empirical claim includes citation tokens (for example `[S1]`).
- Output includes a `Source Table` that resolves citation tokens to concrete sources.
- Output includes a `Self-Audit` section.
- If self-audit contains any `YES`, output includes explicit revision notes.
- If retrieval is insufficient, output is marked `Preliminary` and includes `Follow-up Queries`.
- If disagreement impacts more than 30 percent of major claims, output includes `Conflict Map`.
- Uncertainty and missing-data limitations are explicitly stated.

## Run

```bash
python3 scripts/validate_researcher_output.py agents/researcher/tests/fixtures/sample_pass.md
```
