# Skill: structured-intelligence-skill-creator

## Use When

- A user wants to create a new skill in this repository under `skills/<skill-id>/`.
- A user wants to update an existing repository skill without breaking local conventions.
- The task must produce a Codex- and Claude-compatible skill bundle with matching registry metadata.

## Inputs

- Required:
  - `skill-id` in `kebab-case`
  - human-friendly skill name
  - one-line description
- Optional:
  - owner override
  - version override
  - whether the skill needs `scripts/`, `references/`, or `assets/`
  - example prompts, input schema, or output contract

## Workflow

1. Confirm the task is a skill, not an agent. Skill folders live under `skills/<id>/`.
2. Read only the local files needed to stay aligned with the repository:
   - `docs/conventions.md`
   - `skills/README.md`
   - `skills/registry.yaml`
   - `skills/_templates/skill/*`
   - `references/project-skill-checklist.md` from this skill when exact requirements are needed
3. For a new skill, prefer deterministic scaffolding:
   - If bundled scripts are available, run `scripts/run.sh <skill-id> [repo-root]`
   - Otherwise run the repository helper: `./scripts/bootstrap_new_skill.sh <skill-id>`
4. Replace all template placeholders before finishing:
   - `config.yaml`: `id`, `name`, `version`, `owner`, `description`
   - `SKILL.md`: use conditions, inputs, workflow, output contract, limits
   - `agents/openai.yaml` and `agents/claude.yaml`: matching display text and provider-specific default prompt
5. Keep the bundle minimal:
   - Add scripts only when deterministic execution or repeated logic is useful
   - Add references only when they reduce `SKILL.md` size or hold project-specific detail
   - Do not add generic changelogs, installation guides, or duplicate documentation
6. Register the skill in `skills/registry.yaml` and keep `id`, `name`, and `version` identical to `config.yaml`.
7. Validate with `./scripts/validate_structure.sh` before returning the task as complete.
8. Report the created or updated files, validation result, and install commands for both tools.

## Output Contract

- `skills/<skill-id>/config.yaml` with valid metadata
- `skills/<skill-id>/SKILL.md` with explicit inputs, outputs, and limits
- `skills/<skill-id>/agents/openai.yaml`
- `skills/<skill-id>/agents/claude.yaml`
- optional `scripts/`, `references/`, and `assets/` only when justified
- matching entry in `skills/registry.yaml`
- validation status from `./scripts/validate_structure.sh`
- install commands:
  - `./scripts/install_skill.sh <skill-id>`
  - `./scripts/install_skill.sh <skill-id> --tool claude`

## Limits

- Do not overwrite an existing skill blindly; read the current bundle first.
- Do not leave placeholder strings from the template.
- Do not introduce a registry entry without a real folder and matching config.
- Common failure cases:
  - invalid `kebab-case` id
  - semver mismatch between registry and `config.yaml`
  - missing `agents/openai.yaml` or `agents/claude.yaml`
  - using the wrong default prompt format (`$skill-id` for OpenAI, bare `skill-id` for Claude)
  - skipping `./scripts/validate_structure.sh`
