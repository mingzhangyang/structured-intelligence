#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

import yaml


ROOT = Path(__file__).resolve().parents[1]

REGISTRY_REQUIRED_KEYS = ("id", "name", "version", "path", "config")
AGENT_CONFIG_REQUIRED_KEYS = (
    "id",
    "name",
    "version",
    "owner",
    "description",
    "entrypoints",
    "default_skills",
)
SKILL_CONFIG_REQUIRED_KEYS = (
    "id",
    "name",
    "version",
    "owner",
    "description",
    "entrypoints",
    "default_tools",
)
PROVIDER_REQUIRED_FILENAMES = ("openai.yaml", "claude.yaml")
PROVIDER_INTERFACE_REQUIRED_KEYS = (
    "display_name",
    "short_description",
    "default_prompt",
)
REQUIRED_SKILL_DOC_HEADINGS = (
    "Use When",
    "Inputs",
    "Workflow",
    "Output Contract",
    "Limits",
)

KEBAB_CASE_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)


def is_non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def is_relative_safe_path(path_str: str) -> bool:
    p = Path(path_str)
    return (not p.is_absolute()) and (".." not in p.parts)


def load_yaml(path: Path, errors: list[str]) -> object | None:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{path}: invalid YAML ({exc})")
        return None


def strip_fenced_code_blocks(text: str) -> str:
    return re.sub(r"(?ms)^(```|~~~).*?^\1[ \t]*$", "", text)


def extract_markdown_headings(text: str) -> list[str]:
    return [match.group(1).strip() for match in re.finditer(r"(?m)^##\s+(.+?)\s*$", text)]


def require_keys(path: Path, obj: object, required: tuple[str, ...], errors: list[str]) -> bool:
    if not isinstance(obj, dict):
        errors.append(f"{path}: expected mapping, got {type(obj).__name__}")
        return False
    for key in required:
        if key not in obj:
            errors.append(f"{path}: missing required key '{key}'")
    return not any(msg.startswith(f"{path}: missing required key") for msg in errors)


def validate_common_config_types(
    config_path: Path,
    config: dict,
    default_list_key: str,
    errors: list[str],
) -> None:
    label = str(config_path)
    if not is_non_empty_string(config.get("id")):
        errors.append(f"{label}: 'id' must be a non-empty string")
    elif not KEBAB_CASE_RE.match(config["id"]):
        errors.append(f"{label}: 'id' must be kebab-case")

    if not is_non_empty_string(config.get("name")):
        errors.append(f"{label}: 'name' must be a non-empty string")

    if not is_non_empty_string(config.get("version")):
        errors.append(f"{label}: 'version' must be a non-empty string")
    elif not SEMVER_RE.match(config["version"]):
        errors.append(f"{label}: 'version' must be valid semver (e.g. 1.2.3)")

    if not is_non_empty_string(config.get("owner")):
        errors.append(f"{label}: 'owner' must be a non-empty string")

    if not is_non_empty_string(config.get("description")):
        errors.append(f"{label}: 'description' must be a non-empty string")

    entrypoints = config.get("entrypoints")
    if not isinstance(entrypoints, list) or len(entrypoints) == 0:
        errors.append(f"{label}: 'entrypoints' must be a non-empty list of strings")
    else:
        for i, ep in enumerate(entrypoints):
            if not is_non_empty_string(ep):
                errors.append(f"{label}: 'entrypoints[{i}]' must be a non-empty string")
                continue
            if not is_relative_safe_path(ep):
                errors.append(f"{label}: 'entrypoints[{i}]' must be a safe relative path")
                continue
            target = config_path.parent / ep
            if not target.exists() or not target.is_file():
                errors.append(f"{label}: entrypoint file not found: {ep}")

    default_items = config.get(default_list_key)
    if not isinstance(default_items, list):
        errors.append(f"{label}: '{default_list_key}' must be a list")
    else:
        for i, item in enumerate(default_items):
            if not is_non_empty_string(item):
                errors.append(f"{label}: '{default_list_key}[{i}]' must be a non-empty string")

    if default_list_key == "default_skills" and isinstance(default_items, list):
        for i, skill_id in enumerate(default_items):
            if is_non_empty_string(skill_id) and not KEBAB_CASE_RE.match(skill_id):
                errors.append(f"{label}: 'default_skills[{i}]' must be kebab-case")


def validate_provider_interface_file(path: Path, errors: list[str]) -> None:
    data = load_yaml(path, errors)
    if data is None:
        return
    if not isinstance(data, dict):
        errors.append(f"{path}: expected mapping root")
        return

    interface = data.get("interface")
    if not isinstance(interface, dict):
        errors.append(f"{path}: missing required mapping 'interface'")
        return

    for key in PROVIDER_INTERFACE_REQUIRED_KEYS:
        value = interface.get(key)
        if not is_non_empty_string(value):
            errors.append(f"{path}: 'interface.{key}' must be a non-empty string")


def validate_skill_provider_metadata(skill_dir: Path, entry_label: str, errors: list[str]) -> None:
    agents_dir = skill_dir / "agents"
    if not agents_dir.exists() or not agents_dir.is_dir():
        errors.append(f"{entry_label}: missing provider metadata directory: {agents_dir.relative_to(ROOT)}")
        return

    for filename in PROVIDER_REQUIRED_FILENAMES:
        required_path = agents_dir / filename
        if not required_path.exists() or not required_path.is_file():
            errors.append(
                f"{entry_label}: missing required provider metadata file: {required_path.relative_to(ROOT)}"
            )

    provider_files = sorted(
        {p.resolve(): p for p in list(agents_dir.glob("*.yaml")) + list(agents_dir.glob("*.yml"))}.values(),
        key=lambda p: p.name,
    )
    if not provider_files:
        errors.append(f"{entry_label}: no provider metadata files found under {agents_dir.relative_to(ROOT)}")
        return

    for provider_file in provider_files:
        validate_provider_interface_file(provider_file, errors)


def validate_skill_documentation(skill_dir: Path, entry_label: str, errors: list[str]) -> None:
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists() or not skill_md.is_file():
        errors.append(f"{entry_label}: missing required file: {skill_md.relative_to(ROOT)}")
        return

    text = strip_fenced_code_blocks(skill_md.read_text(encoding="utf-8"))
    headings = {heading.casefold() for heading in extract_markdown_headings(text)}
    for heading in REQUIRED_SKILL_DOC_HEADINGS:
        if heading.casefold() not in headings:
            errors.append(f"{entry_label}: SKILL.md missing required section heading '{heading}'")

    if "limits" in headings:
        limits_match = re.search(r"(?ms)^##\s+Limits\s*$([\s\S]*?)(?=^##\s+|\Z)", text)
        limits_text = limits_match.group(1) if limits_match else ""
        if "failure" not in limits_text.casefold():
            errors.append(
                f"{entry_label}: SKILL.md 'Limits' section should document failure modes or common failure cases"
            )


def validate_registry(
    registry_path: Path,
    root_key: str,
    config_required_keys: tuple[str, ...],
    default_list_key: str,
) -> list[str]:
    errors: list[str] = []
    data = load_yaml(registry_path, errors)
    if data is None:
        return errors
    if not isinstance(data, dict):
        return [f"{registry_path}: expected mapping root"]
    if root_key not in data:
        return [f"{registry_path}: missing required top-level key '{root_key}'"]
    entries = data[root_key]
    if not isinstance(entries, list):
        return [f"{registry_path}: '{root_key}' must be a list"]

    seen_ids: set[str] = set()

    for idx, entry in enumerate(entries):
        entry_label = f"{registry_path}:{root_key}[{idx}]"
        if not isinstance(entry, dict):
            errors.append(f"{entry_label}: expected mapping entry")
            continue

        entry_errors_start = len(errors)

        for key in REGISTRY_REQUIRED_KEYS:
            if key not in entry:
                errors.append(f"{entry_label}: missing required key '{key}'")

        if len(errors) > entry_errors_start:
            continue

        for key in REGISTRY_REQUIRED_KEYS:
            if not is_non_empty_string(entry[key]):
                errors.append(f"{entry_label}: '{key}' must be a non-empty string")

        if len(errors) > entry_errors_start:
            continue

        if not KEBAB_CASE_RE.match(entry["id"]):
            errors.append(f"{entry_label}: 'id' must be kebab-case")
        if not SEMVER_RE.match(entry["version"]):
            errors.append(f"{entry_label}: 'version' must be valid semver (e.g. 1.2.3)")
        if not is_relative_safe_path(entry["path"]):
            errors.append(f"{entry_label}: 'path' must be a safe relative path")
        if not is_relative_safe_path(entry["config"]):
            errors.append(f"{entry_label}: 'config' must be a safe relative path")
        if entry["id"] in seen_ids:
            errors.append(f"{entry_label}: duplicate id '{entry['id']}' in {root_key} registry")
        else:
            seen_ids.add(entry["id"])

        if len(errors) > entry_errors_start:
            continue

        path_parts = Path(entry["path"]).parts
        if root_key == "skills":
            if len(path_parts) != 2 or path_parts[0] != "skills" or path_parts[1] != entry["id"]:
                errors.append(
                    f"{entry_label}: 'path' must be 'skills/{entry['id']}' for registered skills"
                )
            if entry["config"] != f"skills/{entry['id']}/config.yaml":
                errors.append(
                    f"{entry_label}: 'config' must be 'skills/{entry['id']}/config.yaml' for registered skills"
                )
        if root_key == "agents":
            if len(path_parts) != 2 or path_parts[0] != "agents" or path_parts[1] != entry["id"]:
                errors.append(
                    f"{entry_label}: 'path' must be 'agents/{entry['id']}' for registered agents"
                )

        if len(errors) > entry_errors_start:
            continue

        entry_path = ROOT / entry["path"]
        config_path = ROOT / entry["config"]

        if not entry_path.exists() or not entry_path.is_dir():
            errors.append(f"{entry_label}: path does not exist or is not a directory: {entry['path']}")
            continue
        if not config_path.exists() or not config_path.is_file():
            errors.append(f"{entry_label}: config does not exist: {entry['config']}")
            continue

        expected_config_prefix = f"{entry['path'].rstrip('/')}/"
        if not entry["config"].startswith(expected_config_prefix):
            errors.append(
                f"{entry_label}: 'config' should be located under 'path' ({entry['path']})"
            )
            continue

        cfg = load_yaml(config_path, errors)
        if cfg is None:
            continue
        if not require_keys(config_path, cfg, config_required_keys, errors):
            continue
        if not isinstance(cfg, dict):
            continue

        validate_common_config_types(config_path, cfg, default_list_key, errors)
        if len(errors) > entry_errors_start:
            continue

        for key in ("id", "name", "version"):
            if key in cfg and cfg[key] != entry[key]:
                errors.append(
                    f"{entry_label}: '{key}' mismatch with config ({entry[key]!r} != {cfg[key]!r})"
                )

        if root_key == "skills" and "SKILL.md" not in cfg["entrypoints"]:
            errors.append(f"{config_path}: 'entrypoints' should include 'SKILL.md'")
        if root_key == "skills":
            validate_skill_documentation(entry_path, entry_label, errors)
            validate_skill_provider_metadata(entry_path, entry_label, errors)
        if root_key == "agents":
            agent_doc = entry_path / "AGENT.md"
            if not agent_doc.exists() or not agent_doc.is_file():
                errors.append(f"{entry_label}: missing required file: {agent_doc.relative_to(ROOT)}")

    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(
        validate_registry(
            ROOT / "agents/registry.yaml",
            "agents",
            AGENT_CONFIG_REQUIRED_KEYS,
            "default_skills",
        )
    )
    errors.extend(
        validate_registry(
            ROOT / "skills/registry.yaml",
            "skills",
            SKILL_CONFIG_REQUIRED_KEYS,
            "default_tools",
        )
    )

    if errors:
        print("Registry schema validation failed:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Registry schema validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
