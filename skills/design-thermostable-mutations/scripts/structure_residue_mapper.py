#!/usr/bin/env python3
"""
Map WT FASTA sequence positions to structure residue numbering (PDB/mmCIF).

Primary use:
- Resolve sequence numbering vs structure numbering mismatches.
- Produce mapping JSON for downstream scoring wrappers (e.g., FoldX batch runs).
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shlex
from pathlib import Path

VALID_AA = set("ACDEFGHIKLMNPQRSTVWY")
AA3_TO_AA1 = {
    "ALA": "A",
    "ARG": "R",
    "ASN": "N",
    "ASP": "D",
    "CYS": "C",
    "GLN": "Q",
    "GLU": "E",
    "GLY": "G",
    "HIS": "H",
    "ILE": "I",
    "LEU": "L",
    "LYS": "K",
    "MET": "M",
    "PHE": "F",
    "PRO": "P",
    "SER": "S",
    "THR": "T",
    "TRP": "W",
    "TYR": "Y",
    "VAL": "V",
    "MSE": "M",
    "SEC": "C",
    "PYL": "K",
    "ASX": "N",
    "GLX": "Q",
    "UNK": "X",
}


def read_first_fasta(path: str) -> str:
    chunks: list[str] = []
    saw_header = False
    for line in Path(path).read_text().splitlines():
        text = line.strip()
        if not text:
            continue
        if text.startswith(">"):
            if saw_header and chunks:
                break
            saw_header = True
            continue
        chunks.append(text.upper())
    if not chunks:
        raise ValueError(f"No sequence found in FASTA: {path}")
    sequence = "".join(chunks)
    invalid = sorted(set(sequence) - VALID_AA)
    if invalid:
        raise ValueError(
            f"WT FASTA contains non-canonical residues: {''.join(invalid)}. "
            "Use canonical 20-aa alphabet."
        )
    return sequence


def parse_pdb_residues(path: str) -> dict[str, list[dict[str, str]]]:
    by_chain: dict[str, list[dict[str, str]]] = {}
    seen_keys: set[tuple[str, str, str]] = set()
    for line in Path(path).read_text(errors="replace").splitlines():
        record = line[:6].strip()
        if record not in {"ATOM", "HETATM"}:
            continue
        if len(line) < 54:
            continue
        atom = line[12:16].strip()
        altloc = line[16].strip()
        resname = line[17:20].strip().upper()
        chain = (line[21].strip() or "_").upper()
        resseq = line[22:26].strip()
        icode = line[26].strip()
        if atom != "CA":
            continue
        if altloc not in {"", "A", "1"}:
            continue
        aa = AA3_TO_AA1.get(resname, "")
        if aa not in VALID_AA:
            continue
        key = (chain, resseq, icode)
        if key in seen_keys:
            continue
        seen_keys.add(key)
        by_chain.setdefault(chain, []).append(
            {
                "chain": chain,
                "resnum": resseq,
                "icode": icode,
                "aa": aa,
                "resname": resname,
                "residue_id": f"{chain}:{resseq}{icode}",
            }
        )
    return by_chain


def _field_name(headers: list[str], suffix: str) -> str | None:
    for h in headers:
        if h.endswith(suffix):
            return h
    return None


def parse_mmcif_residues(path: str) -> dict[str, list[dict[str, str]]]:
    lines = Path(path).read_text(errors="replace").splitlines()
    by_chain: dict[str, list[dict[str, str]]] = {}
    seen_keys: set[tuple[str, str, str]] = set()
    i = 0
    while i < len(lines):
        text = lines[i].strip()
        if text != "loop_":
            i += 1
            continue
        i += 1
        headers: list[str] = []
        while i < len(lines) and lines[i].strip().startswith("_"):
            headers.append(lines[i].strip())
            i += 1
        if not headers:
            continue
        group_col = _field_name(headers, ".group_PDB")
        if group_col is None:
            continue

        atom_col = _field_name(headers, ".label_atom_id") or _field_name(headers, ".auth_atom_id")
        chain_col = _field_name(headers, ".auth_asym_id") or _field_name(headers, ".label_asym_id")
        comp_col = _field_name(headers, ".auth_comp_id") or _field_name(headers, ".label_comp_id")
        seq_col = _field_name(headers, ".auth_seq_id") or _field_name(headers, ".label_seq_id")
        ins_col = _field_name(headers, ".pdbx_PDB_ins_code")
        alt_col = _field_name(headers, ".label_alt_id")
        if not atom_col or not chain_col or not comp_col or not seq_col:
            continue

        header_index = {h: idx for idx, h in enumerate(headers)}
        n_headers = len(headers)
        while i < len(lines):
            row = lines[i].rstrip()
            stripped = row.strip()
            if not stripped:
                i += 1
                continue
            if stripped.startswith("#"):
                i += 1
                break
            if stripped == "loop_" or stripped.startswith("_"):
                break
            try:
                tokens = shlex.split(row, posix=True)
            except ValueError:
                i += 1
                continue
            if len(tokens) < n_headers:
                i += 1
                continue
            if len(tokens) > n_headers:
                tokens = tokens[:n_headers]

            group = tokens[header_index[group_col]].upper()
            if group not in {"ATOM", "HETATM"}:
                i += 1
                continue
            atom = tokens[header_index[atom_col]].strip()
            if atom != "CA":
                i += 1
                continue

            alt = tokens[header_index[alt_col]].strip() if alt_col else ""
            if alt in {".", "?"}:
                alt = ""
            if alt not in {"", "A", "1"}:
                i += 1
                continue

            chain = tokens[header_index[chain_col]].strip().upper()
            if chain in {"", ".", "?"}:
                chain = "_"
            resname = tokens[header_index[comp_col]].strip().upper()
            seqid = tokens[header_index[seq_col]].strip()
            if seqid in {"", ".", "?"}:
                i += 1
                continue
            icode = tokens[header_index[ins_col]].strip() if ins_col else ""
            if icode in {".", "?"}:
                icode = ""

            aa = AA3_TO_AA1.get(resname, "")
            if aa not in VALID_AA:
                i += 1
                continue

            key = (chain, seqid, icode)
            if key in seen_keys:
                i += 1
                continue
            seen_keys.add(key)
            by_chain.setdefault(chain, []).append(
                {
                    "chain": chain,
                    "resnum": seqid,
                    "icode": icode,
                    "aa": aa,
                    "resname": resname,
                    "residue_id": f"{chain}:{seqid}{icode}",
                }
            )
            i += 1
    return by_chain


def extract_structure_residues(path: str) -> dict[str, list[dict[str, str]]]:
    suffix = Path(path).suffix.lower()
    if suffix in {".pdb", ".ent"}:
        return parse_pdb_residues(path)
    if suffix in {".cif", ".mmcif"}:
        return parse_mmcif_residues(path)
    raise ValueError(f"Unsupported structure format: {path}")


def global_align(seq_a: str, seq_b: str) -> tuple[str, str]:
    match = 2
    mismatch = -1
    gap = -1
    n = len(seq_a)
    m = len(seq_b)
    score = [[0] * (m + 1) for _ in range(n + 1)]
    trace = [[""] * (m + 1) for _ in range(n + 1)]

    for i in range(1, n + 1):
        score[i][0] = score[i - 1][0] + gap
        trace[i][0] = "U"
    for j in range(1, m + 1):
        score[0][j] = score[0][j - 1] + gap
        trace[0][j] = "L"

    for i in range(1, n + 1):
        ai = seq_a[i - 1]
        for j in range(1, m + 1):
            bj = seq_b[j - 1]
            diag = score[i - 1][j - 1] + (match if ai == bj else mismatch)
            up = score[i - 1][j] + gap
            left = score[i][j - 1] + gap
            best = max(diag, up, left)
            score[i][j] = best
            if best == diag:
                trace[i][j] = "D"
            elif best == up:
                trace[i][j] = "U"
            else:
                trace[i][j] = "L"

    aln_a: list[str] = []
    aln_b: list[str] = []
    i = n
    j = m
    while i > 0 or j > 0:
        t = trace[i][j]
        if i > 0 and j > 0 and t == "D":
            aln_a.append(seq_a[i - 1])
            aln_b.append(seq_b[j - 1])
            i -= 1
            j -= 1
        elif i > 0 and (j == 0 or t == "U"):
            aln_a.append(seq_a[i - 1])
            aln_b.append("-")
            i -= 1
        else:
            aln_a.append("-")
            aln_b.append(seq_b[j - 1])
            j -= 1

    return "".join(reversed(aln_a)), "".join(reversed(aln_b))


def build_mapping(
    wt_sequence: str,
    residues: list[dict[str, str]],
) -> dict[str, object]:
    chain_sequence = "".join(r["aa"] for r in residues)
    aln_wt, aln_chain = global_align(wt_sequence, chain_sequence)

    mapping_rows: list[dict[str, object]] = []
    seq_idx = 0
    chain_idx = 0
    aligned_pairs = 0
    matches = 0
    mapped_count = 0

    for a, b in zip(aln_wt, aln_chain):
        has_seq = a != "-"
        has_chain = b != "-"
        if has_seq:
            seq_idx += 1
        if has_chain:
            chain_idx += 1

        if not has_seq:
            continue

        row: dict[str, object] = {
            "seq_pos": seq_idx,
            "wt_aa": a,
            "mapped": False,
        }
        if has_chain:
            aligned_pairs += 1
            residue = residues[chain_idx - 1]
            row.update(
                {
                    "mapped": True,
                    "structure_aa": b,
                    "chain": residue["chain"],
                    "resnum": residue["resnum"],
                    "icode": residue["icode"],
                    "residue_id": residue["residue_id"],
                }
            )
            mapped_count += 1
            if a == b:
                matches += 1
        mapping_rows.append(row)

    identity = (matches / aligned_pairs) if aligned_pairs else 0.0
    coverage = mapped_count / len(wt_sequence) if wt_sequence else 0.0
    return {
        "alignment": {
            "wt_aligned": aln_wt,
            "structure_aligned": aln_chain,
            "aligned_pairs": aligned_pairs,
            "matches": matches,
            "identity": identity,
            "coverage": coverage,
        },
        "sequence_to_structure": mapping_rows,
    }


def choose_chain(
    wt_sequence: str, chains: dict[str, list[dict[str, str]]], requested_chain: str | None
) -> tuple[str, dict[str, object]]:
    if requested_chain:
        chain = requested_chain.upper()
        if chain not in chains:
            raise ValueError(f"Requested chain '{chain}' not found in structure.")
        return chain, build_mapping(wt_sequence, chains[chain])

    best_chain = ""
    best_mapping: dict[str, object] | None = None
    best_score = -1.0
    for chain, residues in sorted(chains.items()):
        mapping = build_mapping(wt_sequence, residues)
        align = mapping["alignment"]
        score = float(align["identity"]) * float(align["coverage"])
        if score > best_score:
            best_score = score
            best_chain = chain
            best_mapping = mapping
    if not best_chain or best_mapping is None:
        raise ValueError("Could not select a structure chain for mapping.")
    return best_chain, best_mapping


def write_tsv(path: str, rows: list[dict[str, object]]) -> None:
    fields = [
        "seq_pos",
        "wt_aa",
        "mapped",
        "structure_aa",
        "chain",
        "resnum",
        "icode",
        "residue_id",
    ]
    with Path(path).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Map WT FASTA positions to structure residue numbering (PDB/mmCIF)."
    )
    parser.add_argument("--sequence-fasta", required=True, help="WT sequence FASTA.")
    parser.add_argument("--structure", required=True, help="Structure path (.pdb/.cif/.mmcif).")
    parser.add_argument("--chain", help="Structure chain ID. If omitted, auto-select best-matching chain.")
    parser.add_argument(
        "--min-identity",
        type=float,
        default=0.5,
        help="Minimum alignment identity threshold for strict mode (default: 0.5).",
    )
    parser.add_argument(
        "--min-coverage",
        type=float,
        default=0.7,
        help="Minimum mapping coverage threshold for strict mode (default: 0.7).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail when identity/coverage fall below thresholds.",
    )
    parser.add_argument("--output-json", required=True, help="Output mapping JSON.")
    parser.add_argument("--output-tsv", help="Optional output TSV table.")
    args = parser.parse_args()

    wt_sequence = read_first_fasta(args.sequence_fasta)
    chains = extract_structure_residues(args.structure)
    if not chains:
        raise ValueError("No parsable protein residues found in structure.")

    selected_chain, mapping = choose_chain(wt_sequence, chains, args.chain)
    align = mapping["alignment"]
    identity = float(align["identity"])
    coverage = float(align["coverage"])

    if args.strict and identity < args.min_identity:
        raise ValueError(
            f"Alignment identity {identity:.3f} below threshold {args.min_identity:.3f}."
        )
    if args.strict and coverage < args.min_coverage:
        raise ValueError(
            f"Mapping coverage {coverage:.3f} below threshold {args.min_coverage:.3f}."
        )

    output = {
        "sequence_fasta": str(Path(args.sequence_fasta)),
        "structure": str(Path(args.structure)),
        "selected_chain": selected_chain,
        "sequence_length": len(wt_sequence),
        "chain_length": len(chains[selected_chain]),
        "identity": identity,
        "coverage": coverage,
        "min_identity": args.min_identity,
        "min_coverage": args.min_coverage,
        "strict": args.strict,
        "alignment": align,
        "sequence_to_structure": mapping["sequence_to_structure"],
    }
    with Path(args.output_json).open("w") as handle:
        json.dump(output, handle, indent=2, sort_keys=True)
        handle.write("\n")

    if args.output_tsv:
        write_tsv(args.output_tsv, mapping["sequence_to_structure"])

    print(
        f"Mapped chain {selected_chain}: identity={identity:.3f} coverage={coverage:.3f} "
        f"({len(chains[selected_chain])} structure residues)."
    )
    print(f"JSON: {args.output_json}")
    if args.output_tsv:
        print(f"TSV: {args.output_tsv}")


if __name__ == "__main__":
    main()
