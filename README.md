# Structured Intelligence

A repository for production-ready AI assets that improve coding, research, and writing throughput.

## What Lives Here

- `agents/`: Task-specific agents with prompts, config, and smoke tests.
- `skills/`: Reusable capabilities packaged with `config.yaml`, `SKILL.md`, scripts, references, and assets.
- `workflows/`: End-to-end operating playbooks for coding, research, and writing.
- `knowledge/`: Reusable source material, notes, and generated outputs.
- `prompts/`: Shared persona and task prompt libraries.
- `scripts/`: Local automation for scaffolding and validation.
- `docs/`: Architecture and contribution conventions.

## Quick Start

### Use The `research` Skill

After cloning this repository:

```bash
# Default target: Codex (~/.codex/skills)
./scripts/install_skill.sh research

# Claude Code (~/.claude/skills)
./scripts/install_skill.sh research --tool claude

# Other tools (custom skills directory)
./scripts/install_skill.sh research --dest ~/.my-tool/skills
```

Then restart your tool session and ask for `research`.

### Use The `rpsblast-assistant` Skill

Install the skill:

```bash
# Default target: Codex (~/.codex/skills)
./scripts/install_skill.sh rpsblast-assistant

# Claude Code (~/.claude/skills)
./scripts/install_skill.sh rpsblast-assistant --tool claude
```

Then restart your tool session and use natural language.

Codex examples:

```text
Use $rpsblast-assistant to tell me what I need to download for a local RPS-BLAST workflow.

Use $rpsblast-assistant to download the minimal CDD database and rpsbproc annotation files into ./db and ./data.

Use $rpsblast-assistant to check whether my local setup is complete for running rpsblast with db/Cdd.

Use $rpsblast-assistant to run rpsblast on ./sequence.fasta against ./db/Cdd with E-value 0.01 and then post-process with rpsbproc.

Use $rpsblast-assistant to explain the format of sequence.out and tell me which part is the real tabular data.
```

Claude Code examples:

```text
Use rpsblast-assistant to tell me what I need to download for a local RPS-BLAST workflow.

Use rpsblast-assistant to download the minimal CDD database and rpsbproc annotation files into ./db and ./data.

Use rpsblast-assistant to check whether my local setup is complete for running rpsblast with db/Cdd.

Use rpsblast-assistant to run rpsblast on ./sequence.fasta against ./db/Cdd with E-value 0.01 and then post-process with rpsbproc.

Use rpsblast-assistant to explain the format of sequence.out and tell me which part is the real tabular data.
```

### Use The `ncbi-eutilities-assistant` Skill

Install the skill:

```bash
# Default target: Codex (~/.codex/skills)
./scripts/install_skill.sh ncbi-eutilities-assistant

# Claude Code (~/.claude/skills)
./scripts/install_skill.sh ncbi-eutilities-assistant --tool claude
```

Then restart your tool session and use natural language.

Codex examples:

```text
Use $ncbi-eutilities-assistant to search PubMed for "CRISPR base editing" and show me the exact E-utilities request first.

Use $ncbi-eutilities-assistant to run a PubMed workflow for "single-cell foundation model" and save the results under ./pubmed-run.

Use $ncbi-eutilities-assistant to run a PubMed review workflow for "large language model systematic review" over the last 365 days and extract structured abstracts into ./pubmed-review.

Use $ncbi-eutilities-assistant to show me the last 7 days of CRISPR progress on PubMed and write a concise update brief under ./crispr-weekly-brief.

Use $ncbi-eutilities-assistant to summarize the last 30 days of base editing research on PubMed into a markdown update brief.

Use $ncbi-eutilities-assistant to fetch PubMed summaries for PMID 39696283 and 39650267 as JSON.
```

Claude Code examples:

```text
Use ncbi-eutilities-assistant to search PubMed for "CRISPR base editing" and show me the exact E-utilities request first.

Use ncbi-eutilities-assistant to run a PubMed workflow for "single-cell foundation model" and save the results under ./pubmed-run.

Use ncbi-eutilities-assistant to run a PubMed review workflow for "large language model systematic review" over the last 365 days and extract structured abstracts into ./pubmed-review.

Use ncbi-eutilities-assistant to show me the last 7 days of CRISPR progress on PubMed and write a concise update brief under ./crispr-weekly-brief.

Use ncbi-eutilities-assistant to summarize the last 30 days of base editing research on PubMed into a markdown update brief.

Use ncbi-eutilities-assistant to fetch PubMed summaries for PMID 39696283 and 39650267 as JSON.
```

### Build This Repository

1. Add an agent from `agents/_templates/agent`.
2. Add a skill from `skills/_templates/skill`.
3. Register both in their `registry.yaml` files.
4. Follow the relevant workflow under `workflows/`.
5. Run `./scripts/validate_structure.sh` before commit.
   It checks the required top-level structure plus registry/schema rules for registered assets.
