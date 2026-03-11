# Provider Metadata

This folder stores provider-specific interface metadata for the skill.

Required files:
- `openai.yaml`
- `claude.yaml`

Each provider file must contain:
- `interface.display_name`
- `interface.short_description`
- `interface.default_prompt`

You can add extra providers as additional `*.yaml` files.
