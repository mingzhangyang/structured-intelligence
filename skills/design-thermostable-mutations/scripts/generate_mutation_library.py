#!/usr/bin/env python3
"""
Generate single-site and multi-site mutation libraries for enzymes.

Examples:
  python scripts/generate_mutation_library.py \
    --sequence-fasta enzyme.fasta \
    --site A45:VILM --site 89:AS --site T132:DE \
    --max-mutations 2 \
    --output-csv mutation_library.csv \
    --output-fasta mutation_library.fasta \
    --output-list mutation_candidates.txt
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import re
from datetime import datetime, timezone
from pathlib import Path

VALID_AA = set("ACDEFGHIKLMNPQRSTVWY")
SITE_RE = re.compile(r"^([A-Z]?)(\d+):([A-Z]+)$")


def parse_position_expression(raw: str) -> set[int]:
    out: set[int] = set()
    text = raw.strip()
    if not text:
        return out
    for token in text.replace(";", ",").split(","):
        item = token.strip()
        if not item:
            continue
        if "-" in item:
            left, right = item.split("-", 1)
            start = int(left.strip())
            end = int(right.strip())
            if start <= 0 or end <= 0:
                raise ValueError(f"Positions must be positive integers: {item!r}")
            if end < start:
                start, end = end, start
            for pos in range(start, end + 1):
                out.add(pos)
            continue
        pos = int(item)
        if pos <= 0:
            raise ValueError(f"Positions must be positive integers: {item!r}")
        out.add(pos)
    return out


def load_position_set(raw: str | None, file_path: str | None) -> set[int]:
    out: set[int] = set()
    if raw:
        out |= parse_position_expression(raw)
    if file_path:
        for line in Path(file_path).read_text().splitlines():
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            out |= parse_position_expression(text)
    return out


def read_first_fasta_sequence(path: str) -> str:
    seq_chunks: list[str] = []
    saw_header = False
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if saw_header and seq_chunks:
                break
            saw_header = True
            continue
        seq_chunks.append(line.upper())
    if not seq_chunks:
        raise ValueError(f"No sequence found in FASTA: {path}")
    sequence = "".join(seq_chunks)
    invalid = sorted(set(sequence) - VALID_AA)
    if invalid:
        raise ValueError(
            f"Sequence contains invalid residues: {''.join(invalid)}. "
            "Use canonical amino acids only."
        )
    return sequence


def parse_site_specs(raw_specs: list[str], sequence: str, include_wt_target: bool, disallow: set[str]) -> dict[int, list[str]]:
    by_pos: dict[int, list[str]] = {}
    seq_len = len(sequence)

    for spec in raw_specs:
        token = spec.strip().upper()
        if not token or token.startswith("#"):
            continue
        match = SITE_RE.match(token)
        if not match:
            raise ValueError(
                f"Invalid site spec '{spec}'. Expected WT?POS:TARGETS, e.g. A45:VILM or 45:VILM."
            )
        wt_given, pos_text, targets_text = match.groups()
        pos = int(pos_text)
        if pos < 1 or pos > seq_len:
            raise ValueError(f"Position {pos} out of range (1..{seq_len}).")

        wt = sequence[pos - 1]
        if wt_given and wt_given != wt:
            raise ValueError(
                f"WT mismatch at {pos}: sequence has '{wt}', but site spec provided '{wt_given}'."
            )

        targets = []
        for aa in targets_text:
            if aa not in VALID_AA:
                raise ValueError(f"Invalid target residue '{aa}' in '{spec}'.")
            if aa in disallow:
                continue
            if not include_wt_target and aa == wt:
                continue
            targets.append(aa)
        if not targets:
            raise ValueError(
                f"No valid targets remain for site '{spec}' after filtering WT/disallowed residues."
            )
        by_pos.setdefault(pos, [])
        by_pos[pos].extend(targets)

    deduped: dict[int, list[str]] = {}
    for pos, residues in by_pos.items():
        seen = set()
        ordered = []
        for aa in residues:
            if aa not in seen:
                seen.add(aa)
                ordered.append(aa)
        deduped[pos] = ordered
    return deduped


def read_site_file(path: str) -> list[str]:
    specs: list[str] = []
    for line in Path(path).read_text().splitlines():
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        specs.append(text)
    return specs


def enumerate_candidates(
    sequence: str, position_targets: dict[int, list[str]], max_mutations: int, max_candidates: int
) -> list[tuple[str, ...]]:
    if max_mutations < 1:
        raise ValueError("--max-mutations must be >= 1.")
    if not position_targets:
        raise ValueError("No mutation sites were provided.")

    positions = sorted(position_targets.keys())
    units_by_pos: dict[int, list[str]] = {}
    for pos in positions:
        wt = sequence[pos - 1]
        units_by_pos[pos] = [f"{wt}{pos}{aa}" for aa in position_targets[pos]]

    candidates: list[tuple[str, ...]] = []
    for k in range(1, min(max_mutations, len(positions)) + 1):
        for chosen_positions in itertools.combinations(positions, k):
            pools = [units_by_pos[pos] for pos in chosen_positions]
            for combo in itertools.product(*pools):
                candidates.append(tuple(combo))
                if len(candidates) > max_candidates:
                    raise ValueError(
                        f"Candidate count exceeded --max-candidates ({max_candidates}). "
                        "Reduce sites/targets or lower max mutation order."
                    )
    return candidates


def apply_mutations(sequence: str, mutation_tuple: tuple[str, ...]) -> str:
    chars = list(sequence)
    for mutation in mutation_tuple:
        wt = mutation[0]
        pos = int(mutation[1:-1])
        mut = mutation[-1]
        if chars[pos - 1] != wt:
            raise ValueError(
                f"Cannot apply {mutation}: sequence has '{chars[pos - 1]}' at position {pos}, expected '{wt}'."
            )
        chars[pos - 1] = mut
    return "".join(chars)


def deduplicate_by_sequence(
    sequence: str, candidates: list[tuple[str, ...]]
) -> tuple[list[tuple[str, ...]], int]:
    seen_sequences: set[str] = set()
    unique: list[tuple[str, ...]] = []
    dropped = 0
    for candidate in candidates:
        mutant = apply_mutations(sequence, candidate)
        if mutant in seen_sequences:
            dropped += 1
            continue
        seen_sequences.add(mutant)
        unique.append(candidate)
    return unique, dropped


def sequence_sha256(sequence: str) -> str:
    return hashlib.sha256(sequence.encode("ascii")).hexdigest()


def write_csv(path: str, sequence: str, candidates: list[tuple[str, ...]]) -> None:
    with Path(path).open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["candidate_id", "mutations", "n_mutations", "mutant_sequence"],
        )
        writer.writeheader()
        for i, candidate in enumerate(candidates, start=1):
            mutation_text = ",".join(candidate)
            writer.writerow(
                {
                    "candidate_id": f"mut_{i:06d}",
                    "mutations": mutation_text,
                    "n_mutations": len(candidate),
                    "mutant_sequence": apply_mutations(sequence, candidate),
                }
            )


def write_fasta(path: str, sequence: str, candidates: list[tuple[str, ...]]) -> None:
    with Path(path).open("w") as handle:
        for i, candidate in enumerate(candidates, start=1):
            mutation_text = ",".join(candidate)
            handle.write(f">mut_{i:06d}|{mutation_text}\n")
            handle.write(f"{apply_mutations(sequence, candidate)}\n")


def write_candidate_list(path: str, candidates: list[tuple[str, ...]]) -> None:
    with Path(path).open("w") as handle:
        for candidate in candidates:
            handle.write(",".join(candidate) + "\n")


def write_metadata(path: str, payload: dict[str, object]) -> None:
    with Path(path).open("w") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate mutation libraries from user-defined sites.")
    parser.add_argument("--sequence-fasta", required=True, help="WT FASTA path.")
    parser.add_argument(
        "--site",
        action="append",
        default=[],
        help="Site spec WT?POS:TARGETS, e.g. A45:VILM or 45:VILM (repeatable).",
    )
    parser.add_argument(
        "--site-file",
        help="Optional file with one site spec per line (same syntax as --site).",
    )
    parser.add_argument(
        "--protected-sites",
        default="",
        help="Comma/range protected positions, e.g. 57,102,195-197.",
    )
    parser.add_argument(
        "--protected-sites-file",
        help="Optional file with protected positions/ranges.",
    )
    parser.add_argument(
        "--allow-missing-protected",
        action="store_true",
        help="Override safety gate and allow library generation without protected positions.",
    )
    parser.add_argument(
        "--allow-protected-sites",
        action="store_true",
        help="Allow mutagenesis at protected positions (explicit override).",
    )
    parser.add_argument(
        "--max-mutations",
        type=int,
        default=1,
        help="Maximum number of substitutions per candidate (default: 1).",
    )
    parser.add_argument(
        "--max-candidates",
        type=int,
        default=5000,
        help="Abort if candidate count exceeds this cap (default: 5000).",
    )
    parser.add_argument(
        "--include-wt-target",
        action="store_true",
        help="Allow target set to include the WT residue.",
    )
    parser.add_argument(
        "--disallow",
        default="",
        help="Residues to exclude from targets, e.g. CP.",
    )
    parser.add_argument(
        "--output-csv",
        required=True,
        help="Output CSV path for mutation library.",
    )
    parser.add_argument(
        "--output-fasta",
        help="Optional output FASTA path for mutant sequences.",
    )
    parser.add_argument(
        "--output-list",
        help="Optional output text file with one mutation candidate per line.",
    )
    parser.add_argument(
        "--allow-duplicate-sequences",
        action="store_true",
        help="Keep candidates that resolve to identical mutant sequences.",
    )
    parser.add_argument(
        "--output-metadata",
        help="Optional JSON metadata report for audit trails.",
    )

    args = parser.parse_args()
    sequence = read_first_fasta_sequence(args.sequence_fasta)

    specs = list(args.site)
    if args.site_file:
        specs.extend(read_site_file(args.site_file))
    if not specs:
        raise ValueError("Provide at least one site via --site or --site-file.")

    disallow = {aa for aa in args.disallow.upper() if aa}
    invalid_disallow = sorted(disallow - VALID_AA)
    if invalid_disallow:
        raise ValueError(f"Invalid residues in --disallow: {''.join(invalid_disallow)}")

    position_targets = parse_site_specs(specs, sequence, args.include_wt_target, disallow)
    protected_sites = load_position_set(args.protected_sites, args.protected_sites_file)

    bad_protected = sorted(pos for pos in protected_sites if pos < 1 or pos > len(sequence))
    if bad_protected:
        raise ValueError(f"Protected-site positions out of range: {bad_protected[:10]}")

    if not protected_sites and not args.allow_missing_protected:
        raise ValueError(
            "Decision-grade library generation requires protected sites by default. "
            "Provide --protected-sites/--protected-sites-file or explicitly set "
            "--allow-missing-protected."
        )

    overlap = sorted(set(position_targets.keys()) & protected_sites)
    if overlap and not args.allow_protected_sites:
        preview = ",".join(str(p) for p in overlap[:20])
        raise ValueError(
            "Site list includes protected positions: "
            f"{preview}. Remove them or explicitly set --allow-protected-sites."
        )

    candidates = enumerate_candidates(sequence, position_targets, args.max_mutations, args.max_candidates)
    pre_dedup_count = len(candidates)
    dropped_duplicates = 0
    if not args.allow_duplicate_sequences:
        candidates, dropped_duplicates = deduplicate_by_sequence(sequence, candidates)

    write_csv(args.output_csv, sequence, candidates)
    if args.output_fasta:
        write_fasta(args.output_fasta, sequence, candidates)
    if args.output_list:
        write_candidate_list(args.output_list, candidates)
    if args.output_metadata:
        payload: dict[str, object] = {
            "created_at_utc": datetime.now(timezone.utc).isoformat(),
            "sequence_length": len(sequence),
            "sequence_sha256": sequence_sha256(sequence),
            "n_sites": len(position_targets),
            "max_mutations": args.max_mutations,
            "candidate_count_before_dedup": pre_dedup_count,
            "candidate_count": len(candidates),
            "dropped_duplicate_sequences": dropped_duplicates,
            "allow_duplicate_sequences": args.allow_duplicate_sequences,
            "allow_missing_protected": args.allow_missing_protected,
            "allow_protected_sites": args.allow_protected_sites,
            "protected_sites": sorted(protected_sites),
            "sites": [
                {
                    "position": pos,
                    "wild_type": sequence[pos - 1],
                    "targets": targets,
                }
                for pos, targets in sorted(position_targets.items())
            ],
        }
        write_metadata(args.output_metadata, payload)

    print(f"Generated {len(candidates)} candidates.")
    if dropped_duplicates:
        print(f"Dropped {dropped_duplicates} duplicate-by-sequence candidates.")
    print(f"CSV: {args.output_csv}")
    if args.output_fasta:
        print(f"FASTA: {args.output_fasta}")
    if args.output_list:
        print(f"List: {args.output_list}")
    if args.output_metadata:
        print(f"Metadata: {args.output_metadata}")


if __name__ == "__main__":
    main()
