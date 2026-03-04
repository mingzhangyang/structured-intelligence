#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <skill-id>"
  exit 1
fi

SKILL_ID="$1"
ROOT="skills/${SKILL_ID}"

if [[ -e "$ROOT" ]]; then
  echo "Skill already exists: $ROOT"
  exit 1
fi

mkdir -p "$ROOT/scripts" "$ROOT/references" "$ROOT/assets" "$ROOT/agents"
cp skills/_templates/skill/SKILL.md "$ROOT/SKILL.md"
cp skills/_templates/skill/config.yaml "$ROOT/config.yaml"
cp skills/_templates/skill/scripts/run.sh "$ROOT/scripts/run.sh"
cp skills/_templates/skill/references/README.md "$ROOT/references/README.md"
cp skills/_templates/skill/agents/README.md "$ROOT/agents/README.md"
cp skills/_templates/skill/agents/openai.yaml "$ROOT/agents/openai.yaml"
cp skills/_templates/skill/agents/claude.yaml "$ROOT/agents/claude.yaml"
touch "$ROOT/assets/.gitkeep"
chmod +x "$ROOT/scripts/run.sh"

echo "Created $ROOT from template"
