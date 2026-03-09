# Structured Intelligence Skill Checklist

Use this file only when you need the exact repository requirements while creating
or updating a skill.

## Required Files

- `skills/<skill-id>/config.yaml`
- `skills/<skill-id>/SKILL.md`
- `skills/<skill-id>/agents/openai.yaml`
- `skills/<skill-id>/agents/claude.yaml`

Optional folders:

- `scripts/`
- `references/`
- `assets/`

## Required Metadata

`config.yaml` must define:

- `id`
- `name`
- `version`
- `owner`
- `description`
- `entrypoints`
- `default_tools`

Registry entries in `skills/registry.yaml` must define:

- `id`
- `name`
- `version`
- `path`
- `config`

The registry `id`, `name`, and `version` must match `config.yaml` exactly.

## Provider Metadata Rules

Both provider files must include:

- `interface.display_name`
- `interface.short_description`
- `interface.default_prompt`

Prompt format differs by provider:

- `agents/openai.yaml`: use `$skill-id`
- `agents/claude.yaml`: use bare `skill-id`

## Creation Sequence

1. Scaffold from `skills/_templates/skill` or run `./scripts/bootstrap_new_skill.sh <skill-id>`.
2. Replace all placeholders immediately.
3. Keep `SKILL.md` concise and explicit about inputs, outputs, and failure modes.
4. Add scripts or references only when they materially improve determinism or reduce prompt size.
5. Register the skill in `skills/registry.yaml`.
6. Run `./scripts/validate_structure.sh`.

## Install Commands

- Codex: `./scripts/install_skill.sh <skill-id>`
- Claude Code: `./scripts/install_skill.sh <skill-id> --tool claude`
