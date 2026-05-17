# Roadmap

Snapshot of in-flight and planned work. Update when scope shifts.

## Done

- Repository layout, registry schema, and `scripts/validate_structure.sh` quality gate.
- CI for structure/registry validation and GitHub Pages deployment.
- Two agents (`ngs-analysis-expert`, `statistical-analysis-expert`) with smoke tests.
- 54 registered skills across research, bioinformatics (NGS / RNA-seq / scRNA-seq / metagenomics), public-database search and download, statistical analysis, and protein stability/design.
- Project landing page, manuscripts, and dynamic sitemap.

## Near Term

1. Skill smoke tests for script-bearing skills (currently optional; promote to validator if maintenance cost stays low).
2. Round out manuscripts for the statistical-analysis-expert agent and its skill family.
3. Provider-metadata audit: confirm Codex (`openai.yaml`) and Claude (`claude.yaml`) default prompts stay aligned with each skill's `Use When` examples.

## Mid Term

1. Benchmark tasks and evaluation harness per workflow (coding / research / writing / genomics / statistics).
2. Publishing flow for reusable skill bundles outside this repository.
3. Cross-skill integration tests for canonical pipelines (e.g., RNA-seq DE end-to-end, WGS variant calling end-to-end).
