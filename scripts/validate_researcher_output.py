#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = [
    "Core Essence",
    "Evolutionary Map",
    "Vulnerabilities and Blind Spots",
    "Cross-Boundary Inspiration",
    "Falsifiable Conclusions",
    "Source Table",
    "Uncertainties",
    "Self-Audit",
]

CLASSIFICATION_VALUES = ("Refinement", "Extension", "Candidate Paradigm Shift")

PARADIGM_CRITERIA_PATTERNS = {
    "Predicts novel phenomena": re.compile(r"predict\w*\s+novel\s+phenomena", re.I),
    "Resolves unresolved anomalies": re.compile(r"resolv\w*\s+unresolved\s+anomal\w*", re.I),
    "Unifies disconnected domains": re.compile(r"unif\w*\s+disconnected\s+domains", re.I),
    "Produces measurable consequences": re.compile(r"produc\w*\s+measurable\s+consequences", re.I),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate researcher markdown output against the smoke contract."
    )
    parser.add_argument("file", help="Path to researcher output markdown file")
    return parser.parse_args()


def collect_headings(text: str) -> list[tuple[int, int, str]]:
    headings: list[tuple[int, int, str]] = []
    for m in re.finditer(r"(?m)^(#{1,6})[ \t]+(.+?)\s*$", text):
        level = len(m.group(1))
        title = m.group(2).strip()
        headings.append((m.start(), level, title))
    return headings


def get_section_text(text: str, headings: list[tuple[int, int, str]], title: str) -> str | None:
    for idx, (start, _level, heading_title) in enumerate(headings):
        if heading_title != title:
            continue
        line_end = text.find("\n", start)
        content_start = len(text) if line_end == -1 else line_end + 1
        content_end = len(text)
        if idx + 1 < len(headings):
            content_end = headings[idx + 1][0]
        return text[content_start:content_end].strip()
    return None


def has_claim_tag(text: str, tag: str) -> bool:
    pattern = re.compile(rf"(\[\s*{tag}\s*\]|{tag}\s*:)", re.I)
    return bool(pattern.search(text))


def split_hypothesis_blocks(section_text: str) -> list[str]:
    markers = list(
        re.finditer(
            r"(?im)^\s*(?:[-*]\s*)?hypothesis(?:\s+\d+|\s+[A-Za-z]|:|\b)",
            section_text,
        )
    )
    if not markers:
        return []

    blocks: list[str] = []
    for i, marker in enumerate(markers):
        start = marker.start()
        end = markers[i + 1].start() if i + 1 < len(markers) else len(section_text)
        block = section_text[start:end].strip()
        if block:
            blocks.append(block)
    return blocks


def extract_citation_tokens(text: str) -> set[str]:
    return set(re.findall(r"\[(S\d+)\]", text))


def validate(text: str) -> list[str]:
    errors: list[str] = []
    headings = collect_headings(text)

    for section in REQUIRED_SECTIONS:
        if get_section_text(text, headings, section) is None:
            errors.append(f"Missing required section heading: '{section}'")

    # Tag checks.
    for tag in ("Observation", "Inference", "Speculation"):
        if not has_claim_tag(text, tag):
            errors.append(f"Missing claim tag usage for '{tag}' (expected '[{tag}]' or '{tag}:').")

    # Falsifiable conclusions checks.
    conclusions = get_section_text(text, headings, "Falsifiable Conclusions")
    if conclusions is None:
        return errors

    blocks = split_hypothesis_blocks(conclusions)
    if len(blocks) < 2:
        errors.append(
            "At least 2 hypothesis blocks are required in 'Falsifiable Conclusions' "
            "(each starting with 'Hypothesis')."
        )
        return errors

    candidate_count = 0
    for idx, block in enumerate(blocks, start=1):
        if not re.search(r"(?i)falsification condition\s*:", block):
            errors.append(f"Hypothesis {idx}: missing 'Falsification condition:'.")

        confidence_match = re.search(r"(?i)confidence estimate\s*:\s*([0-9]*\.?[0-9]+)", block)
        if not confidence_match:
            errors.append(f"Hypothesis {idx}: missing 'Confidence estimate:' in [0,1].")
        else:
            confidence = float(confidence_match.group(1))
            if confidence < 0.0 or confidence > 1.0:
                errors.append(
                    f"Hypothesis {idx}: confidence estimate out of range [0,1] ({confidence})."
                )

        classification_match = re.search(
            r"(?i)classification\s*:\s*(Refinement|Extension|Candidate Paradigm Shift)",
            block,
        )
        if not classification_match:
            errors.append(
                f"Hypothesis {idx}: missing valid 'Classification:' "
                f"({', '.join(CLASSIFICATION_VALUES)})."
            )
            continue

        if classification_match.group(1).lower() == "candidate paradigm shift":
            candidate_count += 1
            matched = [
                name
                for name, pattern in PARADIGM_CRITERIA_PATTERNS.items()
                if pattern.search(block)
            ]
            if len(matched) < 2:
                errors.append(
                    f"Hypothesis {idx}: classification is Candidate Paradigm Shift but only "
                    f"{len(matched)} paradigm criteria found; need at least 2."
                )

    if candidate_count == 0:
        # No failure here; smoke rule is conditional.
        pass

    # Retrieval fallback gate.
    if re.search(r"(?im)^\s*preliminary\s*$", text) or re.search(r"(?i)\bpreliminary\b", text):
        if not re.search(r"(?im)^#{1,6}\s+Follow-up Queries\s*$", text):
            errors.append(
                "Output marked Preliminary but missing required 'Follow-up Queries' section."
            )

    # Conflict gate mention.
    if re.search(r"(?i)\b(3[0-9]|[4-9][0-9]|100)\s*%|\b0\.3[0-9]*\b", text):
        if (
            "conflict" in text.lower()
            and not re.search(r"(?im)^#{1,6}\s+Conflict Map\s*$", text)
        ):
            errors.append(
                "Conflict appears significant but missing 'Conflict Map' section."
            )

    # Citation and source table resolution.
    source_table = get_section_text(text, headings, "Source Table")
    body_without_source = text
    if source_table is not None:
        body_without_source = text.replace(source_table, "")

    cited_tokens = extract_citation_tokens(body_without_source)
    if not cited_tokens:
        errors.append("Missing citation tokens in body (expected tokens like [S1]).")
    elif source_table is not None:
        source_tokens = extract_citation_tokens(source_table)
        unresolved = sorted(cited_tokens - source_tokens)
        if unresolved:
            errors.append(
                "Source Table does not resolve all citation tokens. Missing: "
                + ", ".join(unresolved)
            )

    # Uncertainties checks.
    uncertainties = get_section_text(text, headings, "Uncertainties")
    if uncertainties is not None:
        if not re.search(r"(?i)uncertain|uncertainty|confidence", uncertainties):
            errors.append("Section 'Uncertainties' must explicitly discuss uncertainty/confidence.")
        if not re.search(r"(?i)missing data|data gap|insufficient data|unknown", uncertainties):
            errors.append(
                "Section 'Uncertainties' must explicitly mention missing-data limitations."
            )

    # Self-audit checks.
    self_audit = get_section_text(text, headings, "Self-Audit")
    if self_audit is not None:
        if re.search(r"(?i)\bYES\b", self_audit) and not re.search(
            r"(?i)revision note|revised", text
        ):
            errors.append(
                "Self-Audit contains YES but no explicit revision note was found in output."
            )

    return errors


def main() -> int:
    args = parse_args()
    file_path = Path(args.file)
    if not file_path.exists() or not file_path.is_file():
        print(f"File not found: {file_path}")
        return 1

    text = file_path.read_text(encoding="utf-8")
    errors = validate(text)
    if errors:
        print("Researcher output validation failed:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Researcher output validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
