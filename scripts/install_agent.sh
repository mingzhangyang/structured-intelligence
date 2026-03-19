#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/install_agent.sh <agent-id> [--tool codex|claude] [--dest <agents-dir>] [--skills-dest <skills-dir>] [--force]

Install an agent and its default skills from this repository into local tool directories.

Options:
  --tool        Target tool. Built-ins: codex, claude. Default: codex.
  --dest        Custom agents root directory (overrides --tool for agents).
  --skills-dest Custom skills root directory (overrides --tool for skills).
  --force       Overwrite existing installed agent and skill directories.

For unknown tools, provide both --dest and --skills-dest explicitly.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

AGENT_ID=""
FORCE=0
TOOL="codex"
DEST_OVERRIDE=""
SKILLS_DEST_OVERRIDE=""

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
    --skills-dest)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --skills-dest"
        usage
        exit 1
      fi
      SKILLS_DEST_OVERRIDE="$2"
      shift 2
      ;;
    --*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$AGENT_ID" ]]; then
        AGENT_ID="$1"
      else
        echo "Unexpected argument: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$AGENT_ID" ]]; then
  usage
  exit 1
fi

if [[ ! "$AGENT_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Invalid agent id '$AGENT_ID'. Expected kebab-case."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_PATH="$ROOT_DIR/agents/registry.yaml"
INSTALL_SKILL="$ROOT_DIR/scripts/install_skill.sh"

# Determine target roots based on --tool
AGENTS_TARGET_ROOT=""
SKILLS_TARGET_ROOT=""

case "$TOOL" in
  codex)
    AGENTS_TARGET_ROOT="${CODEX_HOME:-$HOME/.codex}/agents"
    SKILLS_TARGET_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
    ;;
  claude|claude-code)
    AGENTS_TARGET_ROOT="${CLAUDE_HOME:-$HOME/.claude}/agents"
    SKILLS_TARGET_ROOT="${CLAUDE_HOME:-$HOME/.claude}/skills"
    ;;
  *)
    if [[ -z "$DEST_OVERRIDE" || -z "$SKILLS_DEST_OVERRIDE" ]]; then
      echo "Unknown --tool '$TOOL'. Provide both --dest and --skills-dest for custom tool locations."
      exit 1
    fi
    ;;
esac

# Explicit overrides take precedence over --tool defaults
if [[ -n "$DEST_OVERRIDE" ]]; then
  AGENTS_TARGET_ROOT="$DEST_OVERRIDE"
fi
if [[ -n "$SKILLS_DEST_OVERRIDE" ]]; then
  SKILLS_TARGET_ROOT="$SKILLS_DEST_OVERRIDE"
fi

if [[ ! -f "$REGISTRY_PATH" ]]; then
  echo "Missing registry file: $REGISTRY_PATH"
  exit 1
fi

# Resolve agent path from registry
if REL_PATH="$(
  AGENT_ID="$AGENT_ID" REGISTRY_PATH="$REGISTRY_PATH" python3 - <<'PY'
import os
import sys
import yaml

agent_id = os.environ["AGENT_ID"]
registry_path = os.environ["REGISTRY_PATH"]

try:
    with open(registry_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(2)

for entry in data.get("agents", []):
    if isinstance(entry, dict) and entry.get("id") == agent_id:
        path = entry.get("path")
        if isinstance(path, str) and path.strip():
            print(path.strip())
            sys.exit(0)
        sys.exit(3)

sys.exit(4)
PY
 )"; then
  :
else
  rc=$?
  case "$rc" in
    2) echo "Failed to parse agents registry: $REGISTRY_PATH" ;;
    3) echo "Agent '$AGENT_ID' is registered but has invalid 'path' in registry." ;;
    4) echo "Agent '$AGENT_ID' is not registered in agents/registry.yaml." ;;
    *) echo "Failed to resolve agent '$AGENT_ID' from registry." ;;
  esac
  exit 1
fi

if [[ -z "$REL_PATH" ]]; then
  echo "Agent '$AGENT_ID' is not registered in agents/registry.yaml."
  exit 1
fi

if [[ "$REL_PATH" = /* || "$REL_PATH" == *".."* || "$REL_PATH" != agents/* ]]; then
  echo "Agent '$AGENT_ID' resolved to unsafe registry path: $REL_PATH"
  exit 1
fi

SOURCE_DIR="$ROOT_DIR/$REL_PATH"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Registered agent path does not exist: $SOURCE_DIR"
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/AGENT.md" ]]; then
  echo "Agent source missing AGENT.md: $SOURCE_DIR/AGENT.md"
  exit 1
fi

# Install agent directory
TARGET_DIR="$AGENTS_TARGET_ROOT/$AGENT_ID"
mkdir -p "$AGENTS_TARGET_ROOT"

if [[ -e "$TARGET_DIR" && "$FORCE" -ne 1 ]]; then
  echo "Agent target already exists: $TARGET_DIR"
  echo "Re-run with --force to overwrite."
  exit 1
fi

if [[ -e "$TARGET_DIR" ]]; then
  rm -rf "$TARGET_DIR"
fi

cp -R "$SOURCE_DIR" "$TARGET_DIR"
echo "Installed agent '$AGENT_ID' to: $TARGET_DIR"

# Read default_skills from agent config
CONFIG_FILE="$SOURCE_DIR/config.yaml"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Warning: agent config not found at $CONFIG_FILE, skipping skill installation."
  echo "Restart your tool session to ensure the new agent is discovered."
  exit 0
fi

SKILLS="$(
  CONFIG_FILE="$CONFIG_FILE" python3 - <<'PY'
import os
import sys
import yaml

config_file = os.environ["CONFIG_FILE"]

try:
    with open(config_file, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}
    for s in config.get("default_skills", []):
        if isinstance(s, str) and s.strip():
            print(s.strip())
except Exception as e:
    print(f"Warning: could not read default_skills from config: {e}", file=sys.stderr)
PY
)"

if [[ -z "$SKILLS" ]]; then
  echo "No default skills listed in agent config."
  echo "Restart your tool session to ensure the new agent is discovered."
  exit 0
fi

echo ""
echo "Installing default skills for agent '$AGENT_ID'..."

SKILL_FAILED=0
while IFS= read -r SKILL_ID; do
  [[ -z "$SKILL_ID" ]] && continue
  SKILL_ARGS=("$SKILL_ID" "--dest" "$SKILLS_TARGET_ROOT")
  if [[ $FORCE -eq 1 ]]; then
    SKILL_ARGS+=("--force")
  fi
  if bash "$INSTALL_SKILL" "${SKILL_ARGS[@]}"; then
    :
  else
    echo "Warning: failed to install skill '$SKILL_ID'."
    SKILL_FAILED=1
  fi
done <<< "$SKILLS"

echo ""
if [[ $SKILL_FAILED -eq 1 ]]; then
  echo "Agent '$AGENT_ID' installed with some skill failures. See warnings above."
  echo "Restart your tool session to ensure all assets are discovered."
  exit 1
else
  echo "Agent '$AGENT_ID' and all default skills installed successfully."
  echo "Restart your tool session to ensure all assets are discovered."
fi
