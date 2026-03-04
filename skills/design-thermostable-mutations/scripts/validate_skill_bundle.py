#!/usr/bin/env python3
"""
Validate the local skill bundle for structural consistency.

Checks:
- SKILL.md exists and includes frontmatter name/description
- Referenced scripts/references in SKILL.md exist
- Required provider metadata files exist under agents/:
  - openai.yaml
  - claude.yaml
- Each provider metadata file includes interface metadata fields
- evals.json exists and has basic schema integrity
- SKILL.md line-count guidance (warning if > 500)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


PATH_REF_RE = re.compile(r"`((?:scripts|references)/[^`]+)`")
REQUIRED_PROVIDER_FILES = ("openai.yaml", "claude.yaml")


def parse_frontmatter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}
    payload: dict[str, str] = {}
    for line in lines[1:end]:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        payload[key.strip()] = value.strip().strip('"').strip("'")
    return payload


def validate_evals_schema(path: Path) -> list[str]:
    errors: list[str] = []
    if not path.exists():
        return [f"Missing file: {path}"]
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return [f"Invalid JSON in {path}: {exc}"]
    if not isinstance(payload, list) or not payload:
        return [f"{path} must be a non-empty JSON array."]
    for idx, item in enumerate(payload, start=1):
        if not isinstance(item, dict):
            errors.append(f"{path} item #{idx} must be an object.")
            continue
        name = item.get("name")
        prompt = item.get("prompt")
        expectations = item.get("expectations")
        if not isinstance(name, str) or not name.strip():
            errors.append(f"{path} item #{idx} missing non-empty 'name'.")
        if not isinstance(prompt, str) or not prompt.strip():
            errors.append(f"{path} item #{idx} missing non-empty 'prompt'.")
        if not isinstance(expectations, list) or not expectations:
            errors.append(f"{path} item #{idx} missing non-empty 'expectations'.")
            continue
        for e_idx, exp in enumerate(expectations, start=1):
            if not isinstance(exp, str) or not exp.strip():
                errors.append(f"{path} item #{idx} expectation #{e_idx} must be non-empty string.")
    return errors


def validate_provider_yaml(path: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text()
    required = ["interface:", "display_name:", "short_description:", "default_prompt:"]
    for token in required:
        if token not in text:
            errors.append(f"{path} missing required token '{token}'")
    return errors


def validate_provider_metadata(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    agents_dir = skill_dir / "agents"
    if not agents_dir.exists() or not agents_dir.is_dir():
        return [f"Missing provider metadata directory: {agents_dir}"]

    files = sorted(list(agents_dir.glob("*.yaml")) + list(agents_dir.glob("*.yml")))
    if not files:
        return [f"Missing provider metadata file under: {agents_dir}"]

    for filename in REQUIRED_PROVIDER_FILES:
        target = agents_dir / filename
        if not target.exists() or not target.is_file():
            errors.append(f"Missing required provider metadata file: {target}")

    for path in files:
        errors.extend(validate_provider_yaml(path))
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate skill bundle structure and references.")
    parser.add_argument(
        "--skill-dir",
        default=str(Path(__file__).resolve().parents[1]),
        help="Path to skill root (default: parent of scripts/).",
    )
    parser.add_argument(
        "--max-skill-lines",
        type=int,
        default=500,
        help="Guideline threshold for SKILL.md line count warning (default: 500).",
    )
    parser.add_argument(
        "--output-json",
        help="Optional output JSON report path.",
    )
    args = parser.parse_args()

    skill_dir = Path(args.skill_dir).resolve()
    errors: list[str] = []
    warnings: list[str] = []

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        errors.append(f"Missing file: {skill_md}")
    else:
        text = skill_md.read_text()
        line_count = len(text.splitlines())
        if line_count > args.max_skill_lines:
            warnings.append(
                f"{skill_md} has {line_count} lines (guideline <= {args.max_skill_lines})."
            )

        fm = parse_frontmatter(text)
        if not fm.get("name"):
            errors.append("SKILL.md frontmatter missing 'name'.")
        if not fm.get("description"):
            errors.append("SKILL.md frontmatter missing 'description'.")

        refs = sorted(set(PATH_REF_RE.findall(text)))
        for rel in refs:
            target = skill_dir / rel
            if not target.exists():
                errors.append(f"Referenced path missing: {rel}")

    errors.extend(validate_provider_metadata(skill_dir))
    errors.extend(validate_evals_schema(skill_dir / "evals.json"))

    report = {
        "skill_dir": str(skill_dir),
        "errors": errors,
        "warnings": warnings,
        "ok": not errors,
    }

    print(f"errors={len(errors)} warnings={len(warnings)}")
    for msg in errors:
        print(f"ERROR: {msg}")
    for msg in warnings:
        print(f"WARN: {msg}")

    if args.output_json:
        with Path(args.output_json).open("w") as handle:
            json.dump(report, handle, indent=2)
            handle.write("\n")
        print(f"wrote_report_json={args.output_json}")

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
