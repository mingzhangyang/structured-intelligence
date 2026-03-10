# Skills

Skills are reusable capabilities. They should be composable, testable, and well-documented.

## Layout

Each skill should contain:

- `config.yaml`: metadata and runtime entrypoint contract.
- `SKILL.md`: execution guidance and constraints.
- `agents/`: provider metadata adapters (`openai.yaml`, `claude.yaml`, and optional others).
- `scripts/`: utilities used by the skill.
- `references/`: optional targeted references.
- `assets/`: reusable templates or static inputs.

Use `skills/_templates/skill` as the starting point.

Example or reference-only bundles may live under `skills/examples/`, but they should not be added to `skills/registry.yaml` unless they satisfy the same quality gates as production skills.

## Registry Schema

`skills/registry.yaml` uses this shape:

```yaml
skills:
  - id: <skill-id>
    name: <human-friendly-name>
    version: <semver>
    path: skills/<skill-folder>
    config: skills/<skill-folder>/config.yaml
```

`config.yaml` required keys:
- `id`
- `name`
- `version`
- `owner`
- `description`
- `entrypoints`
- `default_tools`

## Provider Metadata Standard

Every skill must include:
- `agents/openai.yaml`
- `agents/claude.yaml`

Each provider file must define:
- `interface.display_name`
- `interface.short_description`
- `interface.default_prompt`
