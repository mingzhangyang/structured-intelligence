#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/install_skill.sh <skill-id> [--tool codex|claude] [--dest <skills-dir>] [--force]

Install a skill from this repository into a local tool skills directory.

Options:
  --tool    Target tool. Built-ins: codex, claude. Default: codex.
  --dest    Custom skills root directory (for other tools or testing).
  --force   Overwrite existing installed skill directory.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

SKILL_ID=""
FORCE=0
TOOL="codex"
DEST_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --tool)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --tool"
        usage
        exit 1
      fi
      TOOL="$2"
      shift 2
      ;;
    --dest)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --dest"
        usage
        exit 1
      fi
      DEST_OVERRIDE="$2"
      shift 2
      ;;
    --*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$SKILL_ID" ]]; then
        SKILL_ID="$1"
      else
        echo "Unexpected argument: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$SKILL_ID" ]]; then
  usage
  exit 1
fi

if [[ ! "$SKILL_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Invalid skill id '$SKILL_ID'. Expected kebab-case."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_PATH="$ROOT_DIR/skills/registry.yaml"
TARGET_ROOT=""

if [[ -n "$DEST_OVERRIDE" ]]; then
  TARGET_ROOT="$DEST_OVERRIDE"
else
  case "$TOOL" in
    codex)
      TARGET_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
      ;;
    claude|claude-code)
      TARGET_ROOT="${CLAUDE_HOME:-$HOME/.claude}/skills"
      ;;
    *)
      echo "Unknown --tool '$TOOL'. Use --dest for custom tool locations."
      exit 1
      ;;
  esac
fi

if [[ ! -f "$REGISTRY_PATH" ]]; then
  echo "Missing registry file: $REGISTRY_PATH"
  exit 1
fi

if REL_PATH="$(
  SKILL_ID="$SKILL_ID" REGISTRY_PATH="$REGISTRY_PATH" python3 - <<'PY'
import os
import sys
import yaml

skill_id = os.environ["SKILL_ID"]
registry_path = os.environ["REGISTRY_PATH"]

try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(2)

for entry in data.get("skills", []):
    if isinstance(entry, dict) and entry.get("id") == skill_id:
        path = entry.get("path")
        if isinstance(path, str) and path.strip():
            print(path.strip())
            sys.exit(0)
        sys.exit(3)  # registered but invalid path field

sys.exit(4)  # missing skill id in registry
PY
 )"; then
  :
else
  rc=$?
  case "$rc" in
    2) echo "Failed to parse skills registry: $REGISTRY_PATH" ;;
    3) echo "Skill '$SKILL_ID' is registered but has invalid 'path' in registry." ;;
    4) echo "Skill '$SKILL_ID' is not registered in skills/registry.yaml." ;;
    *) echo "Failed to resolve skill '$SKILL_ID' from registry." ;;
  esac
  exit 1
fi

if [[ -z "$REL_PATH" ]]; then
  echo "Skill '$SKILL_ID' is not registered in skills/registry.yaml."
  exit 1
fi

SOURCE_DIR="$ROOT_DIR/$REL_PATH"
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Registered skill path does not exist: $SOURCE_DIR"
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/SKILL.md" ]]; then
  echo "Skill source missing SKILL.md: $SOURCE_DIR/SKILL.md"
  exit 1
fi

# Optional pre-install sync hook for skills that mirror canonical sources.
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_${SKILL_ID}_skill.sh"
if [[ -f "$SYNC_SCRIPT" ]]; then
  bash "$SYNC_SCRIPT"
fi

TARGET_DIR="$TARGET_ROOT/$SKILL_ID"
mkdir -p "$TARGET_ROOT"

if [[ -e "$TARGET_DIR" ]]; then
  if [[ "$FORCE" -ne 1 ]]; then
    echo "Target already exists: $TARGET_DIR"
    echo "Re-run with --force to overwrite."
    exit 1
  fi
  rm -rf "$TARGET_DIR"
fi

cp -R "$SOURCE_DIR" "$TARGET_DIR"

echo "Installed skill '$SKILL_ID' to: $TARGET_DIR"
echo "Restart your tool session to ensure the new skill is discovered."
