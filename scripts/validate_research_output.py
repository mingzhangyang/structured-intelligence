#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


CORE_SECTIONS = [
    "Core Essence",
    "Evolutionary Map",
    "Vulnerabilities and Blind Spots",
    "Cross-Boundary Inspiration",
    "Falsifiable Conclusions",
]

APPENDIX_SECTIONS = [
    "Source Table",
    "Uncertainties",
    "Self-Audit",
    "Priority Matrix",
    "Predictions and Calibration Plan",
    "Adversarial Review",
    "Replication Pack",
    "Vault Writeback Log",
]


def strip_fenced_code_blocks(text: str) -> str:
    return re.sub(r"(?ms)^(```|~~~).*?^\1[ \t]*$", "", text)


def extract_headings(text: str) -> list[tuple[int, str]]:
    headings: list[tuple[int, str]] = []
    for match in re.finditer(r"(?m)^(#{1,6})\s+(.+?)\s*$", text):
        title = match.group(2).strip()
        headings.append((match.start(), title))
    return headings


def find_heading_index(headings: list[tuple[int, str]], title: str) -> int | None:
    target = title.casefold()
    for idx, (_offset, heading_title) in enumerate(headings):
        if heading_title.casefold() == target:
            return idx
    return None


def section_bounds(headings: list[tuple[int, str]], text_len: int, title: str) -> tuple[int, int] | None:
    idx = find_heading_index(headings, title)
    if idx is None:
        return None
    start = headings[idx][0]
    end = headings[idx + 1][0] if idx + 1 < len(headings) else text_len
    return start, end


def validate(text: str) -> list[str]:
    errors: list[str] = []
    content = strip_fenced_code_blocks(text)
    headings = extract_headings(content)
    text_len = len(content)

    for title in CORE_SECTIONS + APPENDIX_SECTIONS:
        if find_heading_index(headings, title) is None:
            errors.append(f"Missing required section heading: '{title}'.")

    if errors:
        return errors

    # Ensure the core sections appear in the protocol's required order.
    core_indices = [find_heading_index(headings, title) for title in CORE_SECTIONS]
    if any(idx is None for idx in core_indices):
        return errors
    if core_indices != sorted(core_indices):
        errors.append("Core section headings are out of order.")

    source_bounds = section_bounds(headings, text_len, "Source Table")
    if source_bounds is None:
        return errors
    source_text = content[source_bounds[0] : source_bounds[1]]
    cited_tokens = set(re.findall(r"\[S\d+\]", content))
    source_tokens = set(re.findall(r"\[S\d+\]", source_text))
    unresolved = sorted(cited_tokens - source_tokens)
    if unresolved:
        errors.append(
            "Unresolved citation tokens missing from 'Source Table': "
            + ", ".join(unresolved[:10])
        )

    replication_bounds = section_bounds(headings, text_len, "Replication Pack")
    if replication_bounds is not None:
        replication_text = content[replication_bounds[0] : replication_bounds[1]]
        required_keywords = ("procedure", "pass/fail", "input", "output")
        missing_keywords = [
            keyword for keyword in required_keywords if keyword.lower() not in replication_text.lower()
        ]
        if missing_keywords:
            errors.append(
                "Section 'Replication Pack' is missing expected keywords: "
                + ", ".join(missing_keywords)
            )

    prediction_bounds = section_bounds(headings, text_len, "Predictions and Calibration Plan")
    if prediction_bounds is not None:
        prediction_text = content[prediction_bounds[0] : prediction_bounds[1]]
        has_date = bool(re.search(r"\b\d{4}-\d{2}-\d{2}\b", prediction_text))
        if not has_date:
            errors.append(
                "Section 'Predictions and Calibration Plan' should include at least one checkpoint date (YYYY-MM-DD)."
            )

    vault_bounds = section_bounds(headings, text_len, "Vault Writeback Log")
    if vault_bounds is not None:
        vault_text = content[vault_bounds[0] : vault_bounds[1]]
        if "research_vault/" not in vault_text:
            errors.append(
                "Section 'Vault Writeback Log' should include a `research_vault/` path."
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lightweight validator for research skill markdown output."
    )
    parser.add_argument("file", help="Path to research output markdown file")
    args = parser.parse_args()

    path = Path(args.file)
    if not path.is_file():
        print(f"File not found: {path}")
        return 2

    text = path.read_text(encoding="utf-8")
    errors = validate(text)
    if errors:
        print("Research output validation failed:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Research output validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
