# Structured Intelligence

A repository for production-ready AI assets that improve coding, research, and writing throughput.

Repository: `https://github.com/Scientific-Tooling/structured-intelligence`

License: MIT, see [LICENSE](./LICENSE)

## What Lives Here

- `agents/`: Task-specific agents with prompts, config, and smoke tests.
- `skills/`: Reusable capabilities packaged with `config.yaml`, `SKILL.md`, scripts, references, and assets.
- `workflows/`: End-to-end operating playbooks for coding, research, and writing.
- `knowledge/`: Reusable source material, notes, and generated outputs.
- `prompts/`: Shared persona and task prompt libraries.
- `scripts/`: Local automation for scaffolding and validation.
- `docs/`: Architecture and contribution conventions.

## Availability

This repository is publicly available at `https://github.com/Scientific-Tooling/structured-intelligence`. It contains reusable local skills, agents, workflows, validation scripts, and manuscript-style documentation for selected skills. The repository is intended for local use in AI-assisted coding and research environments that support filesystem-discovered skill bundles.

Relevant project-site, manuscript, and skill materials include:

- `docs/index.html`
- `docs/articles/ncbi-eutilities-assistant.md`
- `docs/articles/rpsblast-assistant.md`
- `manuscripts/`
- `skills/ncbi-eutilities-assistant/`
- `skills/rpsblast-assistant/`

The repository also includes a lightweight project landing page at `docs/index.html` and manuscript web pages under `manuscripts/`, suitable for project-scoped GitHub Pages hosting at `https://scientifictooling.org/structured-intelligence/`.

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

### Use An Agent (with its default skills)

After cloning this repository:

```bash
# Default target: Codex (~/.codex/agents + ~/.codex/skills)
./scripts/install_agent.sh ngs-analysis-expert

# Claude Code (~/.claude/agents + ~/.claude/skills)
./scripts/install_agent.sh ngs-analysis-expert --tool claude

# Other tools (custom directories)
./scripts/install_agent.sh ngs-analysis-expert --dest ~/.my-tool/agents --skills-dest ~/.my-tool/skills
```

The script installs the agent directory and then automatically installs every skill listed in the agent's `default_skills` config. Use `--force` to overwrite existing installations:

```bash
./scripts/install_agent.sh ngs-analysis-expert --tool claude --force
```

Then restart your tool session. The agent and all its skills will be available together.

Codex example:

```text
Use $ngs-analysis-expert to call germline variants from paired-end WGS FASTQs in ./data against GRCh38.
```

Claude Code example:

```text
Use ngs-analysis-expert to call germline variants from paired-end WGS FASTQs in ./data against GRCh38.
```

### Build This Repository

1. Add an agent from `agents/_templates/agent`.
2. Add a skill from `skills/_templates/skill`.
3. Register both in their `registry.yaml` files.
4. Follow the relevant workflow under `workflows/`.
5. Run `./scripts/validate_structure.sh` before commit.
   It checks the required top-level structure plus registry/schema rules for registered assets.
6. Run `./scripts/sync_site_theme.sh` after updating shared page typography in the
   `Scientific-Tooling.github.io` repository.
   It syncs the shared `theme.css` into `docs/` and `manuscripts/` so project pages
   keep the same hero-title and typography system as the organization homepage.

### Shared Page Theme

Use this workflow whenever you add a new public-facing page or change hero-title styles:

1. Treat `Scientific-Tooling.github.io/theme.css` as the source of truth for shared
   typography tokens and semantic title classes.
2. If you change shared title styling there, run `./scripts/sync_site_theme.sh` in
   this repository before editing downstream pages.
3. In every new page, include the shared theme before the page stylesheet:
   - project pages: `./theme.css` then `./site.css`
   - manuscript pages: `./theme.css` or `../theme.css` then the local stylesheet
4. Use semantic classes instead of redefining hero sizes per page:
   - `.title-hero`
   - `.title-hero--wide`
   - `.title-section`
   - `.lede`
   - `.eyebrow`
5. Keep page-specific CSS focused on layout and spacing. Do not redefine shared
   hero-title font sizes or families in page-level styles unless you are changing
   the shared system itself.

## Citation And Reuse

If you reference this repository in scientific writing, cite the repository URL and the access date, and identify the relevant manuscript or skill directory when possible. For example, the skill-focused manuscripts in `docs/` describe the corresponding implementations under `skills/`.

## Independence And Upstream Rights

This repository provides independent, unofficial AI interaction layers around existing scientific tools, APIs, and workflows. It does not claim ownership of the underlying third-party software, databases, services, or documentation, and it does not imply endorsement by the original authors, maintainers, or institutions.

The intent is to add a transparent interface layer for local AI-assisted use, not to reproduce or replace the original applications. Users remain responsible for complying with the licenses, terms of use, attribution requirements, and usage policies of the upstream tools and data sources they invoke through these skills.

## License

This repository is distributed under the MIT License. See [LICENSE](./LICENSE).
