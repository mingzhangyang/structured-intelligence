#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <agent-id>"
  exit 1
fi

AGENT_ID="$1"
if [[ ! "$AGENT_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Invalid agent id '$AGENT_ID'. Expected kebab-case."
  exit 1
fi

AGENT_NAME="$(printf '%s\n' "$AGENT_ID" | awk -F- '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2)}; OFS=" "; $1=$1; print}')"
OWNER="${USER:-unknown}"
DESCRIPTION="TODO: add one-line description."
ROOT="$ROOT_DIR/agents/${AGENT_ID}"

if [[ -e "$ROOT" ]]; then
  echo "Agent already exists: $ROOT"
  exit 1
fi

mkdir -p "$ROOT/prompts" "$ROOT/tests"
cp "$ROOT_DIR/agents/_templates/agent/AGENT.md" "$ROOT/AGENT.md"
cp "$ROOT_DIR/agents/_templates/agent/config.yaml" "$ROOT/config.yaml"
cp "$ROOT_DIR/agents/_templates/agent/prompts/system.md" "$ROOT/prompts/system.md"
cp "$ROOT_DIR/agents/_templates/agent/prompts/task.md" "$ROOT/prompts/task.md"
cp "$ROOT_DIR/agents/_templates/agent/tests/smoke.md" "$ROOT/tests/smoke.md"

AGENT_ID="$AGENT_ID" AGENT_NAME="$AGENT_NAME" OWNER="$OWNER" DESCRIPTION="$DESCRIPTION" ROOT="$ROOT" python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT"])
replacements = {
    "<agent-id>": os.environ["AGENT_ID"],
    "<human-friendly-name>": os.environ["AGENT_NAME"],
    "<owner>": os.environ["OWNER"],
    "<one-line-description>": os.environ["DESCRIPTION"],
}

for rel_path in ("AGENT.md", "config.yaml"):
    path = root / rel_path
    text = path.read_text(encoding="utf-8")
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
PY

echo "Created $ROOT from template"
