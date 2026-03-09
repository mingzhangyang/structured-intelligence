#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run.sh <skill-id> [repo-root]

Bootstrap a new skill in a Structured Intelligence repository by delegating to
the repository's canonical scaffold script.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

SKILL_ID="$1"
REPO_ROOT="${2:-$(pwd)}"
BOOTSTRAP_SCRIPT="$REPO_ROOT/scripts/bootstrap_new_skill.sh"
REGISTRY_PATH="$REPO_ROOT/skills/registry.yaml"
TARGET_DIR="$REPO_ROOT/skills/$SKILL_ID"

if [[ ! "$SKILL_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Invalid skill id '$SKILL_ID'. Expected kebab-case."
  exit 1
fi

if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
  echo "Missing scaffold script: $BOOTSTRAP_SCRIPT"
  exit 1
fi

if [[ ! -f "$REGISTRY_PATH" ]]; then
  echo "Missing skills registry: $REGISTRY_PATH"
  exit 1
fi

if [[ -e "$TARGET_DIR" ]]; then
  echo "Skill already exists: $TARGET_DIR"
  exit 1
fi

(
  cd "$REPO_ROOT"
  "$BOOTSTRAP_SCRIPT" "$SKILL_ID"
)

echo "Scaffolded: skills/$SKILL_ID"
echo "Next steps:"
echo "  1. Fill in skills/$SKILL_ID/config.yaml"
echo "  2. Replace placeholders in skills/$SKILL_ID/SKILL.md and agents/*.yaml"
echo "  3. Add the registry entry to skills/registry.yaml"
echo "  4. Run ./scripts/validate_structure.sh"
