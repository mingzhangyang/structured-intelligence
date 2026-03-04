# Conventions

## Naming

- Agent IDs: `kebab-case` (example: `research-scout`).
- Skill IDs: `kebab-case` (example: `source-summarizer`).
- Prompt files: `snake_case.md`.

## Versioning

- Keep `version` in each agent/skill config.
- Bump `minor` for non-breaking behavior updates.
- Bump `major` when interfaces or expected outputs change.

## Registry Schema

- `agents/registry.yaml` and `skills/registry.yaml` entries must include:
  - `id`
  - `name`
  - `version`
  - `path`
  - `config`
- `agents/<id>/config.yaml` required keys:
  - `id`, `name`, `version`, `owner`, `description`, `entrypoints`, `default_skills`
- `skills/<id>/config.yaml` required keys:
  - `id`, `name`, `version`, `owner`, `description`, `entrypoints`, `default_tools`
- Registry `id/name/version` must match the corresponding config values.
- Strict typing rules enforced by `scripts/validate_registry_schema.py`:
  - `id` must be `kebab-case`
  - `version` must be valid semver (`MAJOR.MINOR.PATCH`)
  - `entrypoints` must be a non-empty list of existing relative file paths
  - `default_skills` and `default_tools` must be string lists
  - Registry `path/config` must be safe relative paths (no absolute paths or `..`)

## Quality Gates

- Every agent should include a smoke test in `tests/`.
- Every skill should document inputs, outputs, and failure modes in `SKILL.md`.
- Every skill should include provider adapter metadata under `agents/`:
  - `openai.yaml`
  - `claude.yaml`
  - each file must define `interface.display_name`, `interface.short_description`, and `interface.default_prompt`
- Add new entries to `registry.yaml` files when introducing assets.
- Run `./scripts/validate_structure.sh` to enforce structure and registry schema checks.
