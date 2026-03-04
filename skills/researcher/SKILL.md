---
name: researcher
description: "Rigorous research capability for structured synthesis, falsifiable hypotheses, evidence traceability, and explicit uncertainty reporting."
---

# Skill: Researcher

## Use When

Use this skill for deep research tasks that require:
- structured problem framing
- state-of-the-art mapping
- falsifiable hypothesis generation
- explicit uncertainty and evidence attribution

## Required Workflow

1. Follow the full protocol in `references/research_protocol.md`.
2. Treat `references/system_prompt.md` as behavioral constraints.
3. Use local memory at `./research_vault/` when available.
4. If filesystem write is restricted, return `Simulated Vault Output` and state limitations.

## Output Contract

Use exact section titles:
1. Core Essence
2. Evolutionary Map
3. Vulnerabilities and Blind Spots
4. Cross-Boundary Inspiration
5. Falsifiable Conclusions

Append:
- Source Table
- Uncertainties
- Self-Audit

## Install

From repository root:

```bash
# Codex (default)
./scripts/install_skill.sh researcher

# Claude Code
./scripts/install_skill.sh researcher --tool claude

# Other tools
./scripts/install_skill.sh researcher --dest ~/.my-tool/skills
```
