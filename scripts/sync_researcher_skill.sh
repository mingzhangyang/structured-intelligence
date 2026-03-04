#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="$ROOT_DIR/agents/researcher"
SKILL_DIR="$ROOT_DIR/skills/researcher"
REF_DIR="$SKILL_DIR/references"

if [[ ! -d "$AGENT_DIR" ]]; then
  echo "Missing agent source directory: $AGENT_DIR"
  exit 1
fi

mkdir -p "$REF_DIR"

cp "$AGENT_DIR/AGENT.md" "$REF_DIR/AGENT.md"
cp "$AGENT_DIR/config.yaml" "$REF_DIR/agent_config.yaml"
cp "$AGENT_DIR/prompts/system.md" "$REF_DIR/system_prompt.md"
cp "$AGENT_DIR/prompts/research_protocol.md" "$REF_DIR/research_protocol.md"

echo "Synced researcher references from agents/researcher -> skills/researcher/references"
