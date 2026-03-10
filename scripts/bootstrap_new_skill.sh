#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <skill-id>"
  exit 1
fi

SKILL_ID="$1"
if [[ ! "$SKILL_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Invalid skill id '$SKILL_ID'. Expected kebab-case."
  exit 1
fi

SKILL_NAME="$(printf '%s\n' "$SKILL_ID" | awk -F- '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2)}; OFS=" "; $1=$1; print}')"
OWNER="${USER:-unknown}"
DESCRIPTION="TODO: add one-line description."
ROOT="$ROOT_DIR/skills/${SKILL_ID}"

if [[ -e "$ROOT" ]]; then
  echo "Skill already exists: $ROOT"
  exit 1
fi

mkdir -p "$ROOT/scripts" "$ROOT/references" "$ROOT/assets" "$ROOT/agents"
cp "$ROOT_DIR/skills/_templates/skill/SKILL.md" "$ROOT/SKILL.md"
cp "$ROOT_DIR/skills/_templates/skill/config.yaml" "$ROOT/config.yaml"
cp "$ROOT_DIR/skills/_templates/skill/scripts/run.sh" "$ROOT/scripts/run.sh"
cp "$ROOT_DIR/skills/_templates/skill/references/README.md" "$ROOT/references/README.md"
cp "$ROOT_DIR/skills/_templates/skill/agents/README.md" "$ROOT/agents/README.md"
cp "$ROOT_DIR/skills/_templates/skill/agents/openai.yaml" "$ROOT/agents/openai.yaml"
cp "$ROOT_DIR/skills/_templates/skill/agents/claude.yaml" "$ROOT/agents/claude.yaml"
touch "$ROOT/assets/.gitkeep"
chmod +x "$ROOT/scripts/run.sh"

SKILL_ID="$SKILL_ID" SKILL_NAME="$SKILL_NAME" OWNER="$OWNER" DESCRIPTION="$DESCRIPTION" ROOT="$ROOT" python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT"])
replacements = {
    "<skill-id>": os.environ["SKILL_ID"],
    "<human-friendly-name>": os.environ["SKILL_NAME"],
    "<owner>": os.environ["OWNER"],
    "<one-line-description>": os.environ["DESCRIPTION"],
}

for rel_path in ("SKILL.md", "config.yaml", "agents/openai.yaml", "agents/claude.yaml"):
    path = root / rel_path
    text = path.read_text(encoding="utf-8")
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
PY

echo "Created $ROOT from template"
