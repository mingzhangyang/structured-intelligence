#!/usr/bin/env python3
"""
Discover and rank mutation-site candidates for enzyme engineering.

This script is a deterministic front-end for site prioritization before library
enumeration. It applies structural heuristics and functional guardrails, then
emits ranked sites and optional site specs that can be passed to
generate_mutation_library.py via --site-file.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shlex
import statistics
import sys
from pathlib import Path

from structure_residue_mapper import (
    AA3_TO_AA1,
    VALID_AA,
    choose_chain,
    extract_structure_residues,
    read_first_fasta,
)


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


def _mmcif_field(headers: list[str], suffixes: tuple[str, ...]) -> str | None:
    for suffix in suffixes:
        for header in headers:
            if header.endswith(suffix):
                return header
    return None


def parse_pdb_ca_records(path: str) -> dict[str, dict[str, dict[str, object]]]:
    by_chain: dict[str, dict[str, dict[str, object]]] = {}
    seen: set[tuple[str, str, str]] = set()
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
        if key in seen:
            continue
        seen.add(key)
        residue_id = f"{chain}:{resseq}{icode}"
        try:
            x = float(line[30:38].strip())
            y = float(line[38:46].strip())
            z = float(line[46:54].strip())
        except ValueError:
            continue
        bfac: float | None = None
        if len(line) >= 66:
            try:
                bfac = float(line[60:66].strip())
            except ValueError:
                bfac = None
        by_chain.setdefault(chain, {})
        by_chain[chain][residue_id] = {
            "chain": chain,
            "resnum": resseq,
            "icode": icode,
            "residue_id": residue_id,
            "aa": aa,
            "coord": (x, y, z),
            "bfactor": bfac,
        }
    return by_chain


def parse_mmcif_ca_records(path: str) -> dict[str, dict[str, dict[str, object]]]:
    lines = Path(path).read_text(errors="replace").splitlines()
    by_chain: dict[str, dict[str, dict[str, object]]] = {}
    seen: set[tuple[str, str, str]] = set()
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

        group_col = _mmcif_field(headers, (".group_PDB",))
        atom_col = _mmcif_field(headers, (".label_atom_id", ".auth_atom_id"))
        chain_col = _mmcif_field(headers, (".auth_asym_id", ".label_asym_id"))
        comp_col = _mmcif_field(headers, (".auth_comp_id", ".label_comp_id"))
        seq_col = _mmcif_field(headers, (".auth_seq_id", ".label_seq_id"))
        ins_col = _mmcif_field(headers, (".pdbx_PDB_ins_code",))
        alt_col = _mmcif_field(headers, (".label_alt_id",))
        x_col = _mmcif_field(headers, (".Cartn_x",))
        y_col = _mmcif_field(headers, (".Cartn_y",))
        z_col = _mmcif_field(headers, (".Cartn_z",))
        b_col = _mmcif_field(headers, (".B_iso_or_equiv",))
        if not group_col or not atom_col or not chain_col or not comp_col or not seq_col:
            continue
        if not x_col or not y_col or not z_col:
            continue

        idx = {h: j for j, h in enumerate(headers)}
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

            group = tokens[idx[group_col]].upper()
            if group not in {"ATOM", "HETATM"}:
                i += 1
                continue
            atom = tokens[idx[atom_col]].strip()
            if atom != "CA":
                i += 1
                continue

            alt = tokens[idx[alt_col]].strip() if alt_col else ""
            if alt in {".", "?"}:
                alt = ""
            if alt not in {"", "A", "1"}:
                i += 1
                continue

            chain = tokens[idx[chain_col]].strip().upper()
            if chain in {"", ".", "?"}:
                chain = "_"
            resname = tokens[idx[comp_col]].strip().upper()
            seqid = tokens[idx[seq_col]].strip()
            if seqid in {"", ".", "?"}:
                i += 1
                continue
            icode = tokens[idx[ins_col]].strip() if ins_col else ""
            if icode in {".", "?"}:
                icode = ""
            aa = AA3_TO_AA1.get(resname, "")
            if aa not in VALID_AA:
                i += 1
                continue
            key = (chain, seqid, icode)
            if key in seen:
                i += 1
                continue

            try:
                x = float(tokens[idx[x_col]])
                y = float(tokens[idx[y_col]])
                z = float(tokens[idx[z_col]])
            except ValueError:
                i += 1
                continue

            bfac: float | None = None
            if b_col:
                b_text = tokens[idx[b_col]].strip()
                if b_text not in {"", ".", "?"}:
                    try:
                        bfac = float(b_text)
                    except ValueError:
                        bfac = None

            seen.add(key)
            residue_id = f"{chain}:{seqid}{icode}"
            by_chain.setdefault(chain, {})
            by_chain[chain][residue_id] = {
                "chain": chain,
                "resnum": seqid,
                "icode": icode,
                "residue_id": residue_id,
                "aa": aa,
                "coord": (x, y, z),
                "bfactor": bfac,
            }
            i += 1
    return by_chain


def extract_ca_records(path: str) -> dict[str, dict[str, dict[str, object]]]:
    suffix = Path(path).suffix.lower()
    if suffix in {".pdb", ".ent"}:
        return parse_pdb_ca_records(path)
    if suffix in {".cif", ".mmcif"}:
        return parse_mmcif_ca_records(path)
    raise ValueError(f"Unsupported structure format: {path}")


def dist(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def classify_exposure(contact_count: int | None) -> str:
    if contact_count is None:
        return "unknown"
    if contact_count <= 8:
        return "surface"
    if contact_count <= 14:
        return "boundary"
    return "core"


def classify_active_shell(min_active_distance: float | None) -> str:
    if min_active_distance is None:
        return "unknown"
    if min_active_distance <= 6.0:
        return "first_shell"
    if min_active_distance <= 12.0:
        return "second_shell"
    return "distal"


def suggest_targets(
    wt: str,
    exposure: str,
    bfactor_z: float | None,
    objective: str,
    max_targets: int,
) -> list[str]:
    if objective == "ph-tolerance":
        order = "DEKRQNHSTAILVFMWY"
    elif objective == "solvent-tolerance":
        order = "DEKRQNSTAHILVFMWY"
    elif objective == "thermostability":
        if exposure == "core":
            order = "ILVFMWAYTNQST"
        elif exposure == "surface":
            order = "DEKRQNSTAILVFM"
        else:
            order = "AILVFMWYQNSTDEKR"
    else:
        if exposure == "core":
            order = "AILVFMWYTNQST"
        elif exposure == "surface":
            order = "DEKRQNSTAHILV"
        else:
            order = "AILVSTNQDEKRFMWY"

    if bfactor_z is not None and bfactor_z >= 1.0:
        order += "P"

    out: list[str] = []
    seen: set[str] = set()
    for aa in order:
        if aa == wt:
            continue
        if aa not in VALID_AA:
            continue
        if aa in seen:
            continue
        seen.add(aa)
        out.append(aa)
        if len(out) >= max_targets:
            break
    return out


def round_or_blank(value: float | None, ndigits: int = 3) -> str:
    if value is None:
        return ""
    return str(round(value, ndigits))


def main() -> None:
    parser = argparse.ArgumentParser(description="Discover and rank mutation-site candidates.")
    parser.add_argument("--sequence-fasta", required=True, help="WT sequence FASTA.")
    parser.add_argument(
        "--structure",
        help="Optional structure path (.pdb/.cif/.mmcif). If omitted, sequence-only ranking is used.",
    )
    parser.add_argument("--chain", help="Structure chain ID. If omitted, auto-select best matching chain.")
    parser.add_argument(
        "--objective",
        default="mixed",
        choices=["mixed", "thermostability", "ph-tolerance", "solvent-tolerance"],
        help="Primary engineering objective (default: mixed).",
    )
    parser.add_argument("--active-site", default="", help="Comma/range positions, e.g. 70,73,130-132")
    parser.add_argument("--cofactor-sites", default="", help="Comma/range positions in cofactor/metal contact shell.")
    parser.add_argument("--disulfide-sites", default="", help="Comma/range disulfide-associated positions.")
    parser.add_argument("--interface-sites", default="", help="Comma/range interface-sensitive positions.")
    parser.add_argument("--conserved-sites", default="", help="Comma/range conserved positions.")
    parser.add_argument("--blocklist-sites", default="", help="Comma/range user-defined blocked positions.")
    parser.add_argument("--prefer-sites", default="", help="Comma/range user-prioritized positions.")
    parser.add_argument("--active-site-file", help="Optional file with active-site positions.")
    parser.add_argument("--cofactor-sites-file", help="Optional file with cofactor-site positions.")
    parser.add_argument("--disulfide-sites-file", help="Optional file with disulfide-site positions.")
    parser.add_argument("--interface-sites-file", help="Optional file with interface-site positions.")
    parser.add_argument("--conserved-sites-file", help="Optional file with conserved-site positions.")
    parser.add_argument("--blocklist-sites-file", help="Optional file with blocked positions.")
    parser.add_argument("--prefer-sites-file", help="Optional file with preferred positions.")
    parser.add_argument(
        "--allow-missing-functional-constraints",
        action="store_true",
        help=(
            "Override decision-grade safety gate and allow execution when no active/cofactor/"
            "disulfide/blocklist positions are provided."
        ),
    )
    parser.add_argument(
        "--allow-functional-sites",
        action="store_true",
        help="Allow (but penalize) active/cofactor/disulfide/blocklisted positions in ranking.",
    )
    parser.add_argument(
        "--contact-radius",
        type=float,
        default=10.0,
        help="CA-contact radius in Angstrom for exposure proxy (default: 10.0).",
    )
    parser.add_argument("--top-n", type=int, default=30, help="Number of top unblocked sites to mark selected.")
    parser.add_argument(
        "--include-blocked",
        action="store_true",
        help="Include blocked positions in selected list (still marked as blocked).",
    )
    parser.add_argument(
        "--max-targets-per-site",
        type=int,
        default=8,
        help="Max suggested substitutions per site in site specs (default: 8).",
    )
    parser.add_argument("--output-csv", required=True, help="Output CSV for ranked site candidates.")
    parser.add_argument("--output-json", help="Optional JSON summary output.")
    parser.add_argument(
        "--output-site-specs",
        help="Optional output file with one WT?POS:TARGETS site spec per selected site.",
    )

    args = parser.parse_args()
    sequence = read_first_fasta(args.sequence_fasta)
    seq_len = len(sequence)

    active_sites = load_position_set(args.active_site, args.active_site_file)
    cofactor_sites = load_position_set(args.cofactor_sites, args.cofactor_sites_file)
    disulfide_sites = load_position_set(args.disulfide_sites, args.disulfide_sites_file)
    interface_sites = load_position_set(args.interface_sites, args.interface_sites_file)
    conserved_sites = load_position_set(args.conserved_sites, args.conserved_sites_file)
    blocklist_sites = load_position_set(args.blocklist_sites, args.blocklist_sites_file)
    prefer_sites = load_position_set(args.prefer_sites, args.prefer_sites_file)

    for label, positions in (
        ("active-site", active_sites),
        ("cofactor-sites", cofactor_sites),
        ("disulfide-sites", disulfide_sites),
        ("interface-sites", interface_sites),
        ("conserved-sites", conserved_sites),
        ("blocklist-sites", blocklist_sites),
        ("prefer-sites", prefer_sites),
    ):
        bad = sorted(pos for pos in positions if pos < 1 or pos > seq_len)
        if bad:
            raise ValueError(f"{label} contains out-of-range positions: {bad[:10]}")

    functional_constraints = active_sites | cofactor_sites | disulfide_sites | blocklist_sites
    if not functional_constraints:
        if args.allow_missing_functional_constraints:
            print(
                "Warning: no functional constraints provided; running due to explicit override.",
                file=sys.stderr,
            )
        else:
            raise ValueError(
                "Decision-grade site discovery requires functional constraints by default. "
                "Provide at least one of --active-site, --cofactor-sites, --disulfide-sites, "
                "or --blocklist-sites (or corresponding *-file), or explicitly set "
                "--allow-missing-functional-constraints."
            )

    mapping_rows: list[dict[str, object]] = []
    selected_chain = ""
    coords_by_residue: dict[str, dict[str, object]] = {}

    if args.structure:
        chains = extract_structure_residues(args.structure)
        selected_chain, mapping_payload = choose_chain(sequence, chains, args.chain)
        mapping_rows = list(mapping_payload["sequence_to_structure"])
        coord_chains = extract_ca_records(args.structure)
        coords_by_residue = coord_chains.get(selected_chain, {})
        if not coords_by_residue:
            raise ValueError(f"No CA records found for selected chain '{selected_chain}'.")
    else:
        for i, aa in enumerate(sequence, start=1):
            mapping_rows.append({"seq_pos": i, "wt_aa": aa, "mapped": False})

    mapped_rows = [row for row in mapping_rows if bool(row.get("mapped", False))]
    seq_to_coord: dict[int, tuple[float, float, float]] = {}
    seq_to_b: dict[int, float | None] = {}
    seq_to_residue_id: dict[int, str] = {}
    seq_to_resnum: dict[int, str] = {}

    for row in mapped_rows:
        seq_pos = int(row["seq_pos"])
        residue_id = str(row.get("residue_id", ""))
        rec = coords_by_residue.get(residue_id)
        if not rec:
            continue
        seq_to_coord[seq_pos] = rec["coord"]  # type: ignore[index]
        seq_to_b[seq_pos] = rec.get("bfactor")  # type: ignore[assignment]
        seq_to_residue_id[seq_pos] = residue_id
        seq_to_resnum[seq_pos] = str(rec.get("resnum", ""))

    bvals = [float(v) for v in seq_to_b.values() if isinstance(v, (int, float))]
    b_mean = statistics.mean(bvals) if bvals else None
    b_std = statistics.pstdev(bvals) if len(bvals) >= 2 else None

    all_coords = list(seq_to_coord.values())
    active_coords = [seq_to_coord[pos] for pos in sorted(active_sites) if pos in seq_to_coord]

    rows: list[dict[str, object]] = []
    for pos in range(1, seq_len + 1):
        wt = sequence[pos - 1]
        mapped = pos in seq_to_coord
        coord = seq_to_coord.get(pos)

        contact_count: int | None = None
        if coord is not None:
            count = 0
            for other in all_coords:
                if other is coord:
                    continue
                if dist(coord, other) <= args.contact_radius:
                    count += 1
            contact_count = count
        exposure = classify_exposure(contact_count)

        bfactor = seq_to_b.get(pos)
        b_z: float | None = None
        if isinstance(bfactor, (int, float)) and b_mean is not None and b_std and b_std > 0:
            b_z = (float(bfactor) - b_mean) / b_std

        min_active_distance: float | None = None
        if coord is not None and active_coords:
            min_active_distance = min(dist(coord, a) for a in active_coords)
        elif pos in active_sites:
            min_active_distance = 0.0
        active_shell = classify_active_shell(min_active_distance)

        blocked_tags: list[str] = []
        if pos in blocklist_sites:
            blocked_tags.append("user_blocklist")
        if pos in active_sites:
            blocked_tags.append("active_site")
        if pos in cofactor_sites:
            blocked_tags.append("cofactor_or_metal_contact")
        if pos in disulfide_sites:
            blocked_tags.append("native_disulfide")
        blocked = bool(blocked_tags) and not args.allow_functional_sites

        risk_tags: list[str] = []
        if pos in conserved_sites:
            risk_tags.append("conserved")
        if pos in interface_sites:
            risk_tags.append("interface_sensitive")
        if active_shell == "first_shell":
            risk_tags.append("active_first_shell")
        if wt in {"G", "P"}:
            risk_tags.append("gly_pro_context")
        if wt == "C" and pos not in disulfide_sites:
            risk_tags.append("cysteine_context")
        for tag in blocked_tags:
            if tag not in risk_tags:
                risk_tags.append(tag)

        score = 0.0
        rationale: list[str] = []

        if mapped:
            score += 0.2
            rationale.append("mapped_to_structure")
        else:
            score -= 0.6
            rationale.append("unmapped_position_penalty")

        if exposure == "boundary":
            score += 1.0
            rationale.append("boundary_position_preferred")
        elif exposure == "surface":
            score += 0.8
            rationale.append("surface_position_preferred")
        elif exposure == "core":
            score += 0.2
            rationale.append("core_position_caution")

        if active_shell == "second_shell":
            score += 1.2
            rationale.append("second_shell_preferred")
        elif active_shell == "distal":
            score += 0.4
            rationale.append("distal_from_active_site")
        elif active_shell == "first_shell":
            score -= 2.5
            rationale.append("first_shell_penalty")

        if b_z is not None:
            if b_z >= 1.5:
                score += 1.0
                rationale.append("high_flexibility_signal")
            elif b_z >= 0.5:
                score += 0.5
                rationale.append("moderate_flexibility_signal")

        if pos in conserved_sites:
            score -= 1.8
            rationale.append("conservation_penalty")
        if pos in interface_sites:
            score -= 1.2
            rationale.append("interface_penalty")
        if wt in {"G", "P"}:
            score -= 0.6
            rationale.append("gly_pro_penalty")
        if wt == "C":
            score -= 0.8
            rationale.append("cysteine_penalty")
        if pos in prefer_sites:
            score += 0.8
            rationale.append("user_preferred_boost")

        if blocked:
            score -= 4.0
            rationale.append("blocked_functional_site")
        elif blocked_tags and args.allow_functional_sites:
            score -= 2.0
            rationale.append("functional_site_allowed_with_penalty")

        targets = suggest_targets(wt, exposure, b_z, args.objective, args.max_targets_per_site)
        site_spec = f"{wt}{pos}:{''.join(targets)}" if targets else ""

        evidence_count = 0
        if mapped:
            evidence_count += 1
        if contact_count is not None:
            evidence_count += 1
        if b_z is not None:
            evidence_count += 1
        if active_shell != "unknown":
            evidence_count += 1
        if evidence_count >= 3:
            confidence = "high"
        elif evidence_count == 2:
            confidence = "medium"
        else:
            confidence = "low"

        if blocked:
            priority = "blocked"
        elif score >= 2.5:
            priority = "high"
        elif score >= 1.2:
            priority = "medium"
        else:
            priority = "low"

        rows.append(
            {
                "seq_pos": pos,
                "wt_aa": wt,
                "mapped": mapped,
                "chain": selected_chain if mapped else "",
                "resnum": seq_to_resnum.get(pos, ""),
                "residue_id": seq_to_residue_id.get(pos, ""),
                "candidate_score": round(score, 4),
                "priority": priority,
                "confidence": confidence,
                "blocked": blocked,
                "block_reason": ";".join(blocked_tags),
                "risk_tags": ";".join(sorted(set(risk_tags))),
                "min_active_distance": round_or_blank(min_active_distance, 3),
                "active_shell": active_shell,
                "contact_count": "" if contact_count is None else contact_count,
                "exposure_class": exposure,
                "bfactor": round_or_blank(float(bfactor), 3) if isinstance(bfactor, (int, float)) else "",
                "bfactor_z": round_or_blank(b_z, 3),
                "recommended_targets": "".join(targets),
                "site_spec": site_spec,
                "rationale": ";".join(rationale),
            }
        )

    rows.sort(
        key=lambda r: (
            1 if bool(r["blocked"]) else 0,
            -float(r["candidate_score"]),
            int(r["seq_pos"]),
        )
    )

    selected_pool = rows if args.include_blocked else [r for r in rows if not bool(r["blocked"])]
    selected = selected_pool[: max(0, args.top_n)]
    selected_keys = {(int(r["seq_pos"]), str(r["wt_aa"])) for r in selected}

    for i, row in enumerate(rows, start=1):
        row["rank"] = i
        row["selected"] = (int(row["seq_pos"]), str(row["wt_aa"])) in selected_keys

    fields = [
        "rank",
        "selected",
        "seq_pos",
        "wt_aa",
        "mapped",
        "chain",
        "resnum",
        "residue_id",
        "candidate_score",
        "priority",
        "confidence",
        "blocked",
        "block_reason",
        "risk_tags",
        "min_active_distance",
        "active_shell",
        "contact_count",
        "exposure_class",
        "bfactor",
        "bfactor_z",
        "recommended_targets",
        "site_spec",
        "rationale",
    ]
    with Path(args.output_csv).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    if args.output_site_specs:
        with Path(args.output_site_specs).open("w") as handle:
            for row in selected:
                spec = str(row.get("site_spec", "")).strip()
                if not spec:
                    continue
                handle.write(spec + "\n")

    summary = {
        "sequence_length": seq_len,
        "structure_provided": bool(args.structure),
        "selected_chain": selected_chain if args.structure else "",
        "objective": args.objective,
        "top_n": args.top_n,
        "include_blocked": args.include_blocked,
        "allow_functional_sites": args.allow_functional_sites,
        "allow_missing_functional_constraints": args.allow_missing_functional_constraints,
        "counts": {
            "total_positions": len(rows),
            "blocked_positions": sum(1 for r in rows if bool(r["blocked"])),
            "selected_positions": len(selected),
            "high_priority_positions": sum(
                1 for r in rows if str(r["priority"]) == "high" and not bool(r["blocked"])
            ),
            "mapped_positions": sum(1 for r in rows if bool(r["mapped"])),
        },
        "inputs": {
            "active_sites": sorted(active_sites),
            "cofactor_sites": sorted(cofactor_sites),
            "disulfide_sites": sorted(disulfide_sites),
            "interface_sites": sorted(interface_sites),
            "conserved_sites": sorted(conserved_sites),
            "blocklist_sites": sorted(blocklist_sites),
            "prefer_sites": sorted(prefer_sites),
        },
    }
    if args.output_json:
        with Path(args.output_json).open("w") as handle:
            json.dump(summary, handle, indent=2, sort_keys=True)
            handle.write("\n")

    print(f"Wrote ranked site candidates: {args.output_csv}")
    print(f"Selected sites: {len(selected)}")
    if args.output_site_specs:
        print(f"Wrote site specs: {args.output_site_specs}")
    if args.output_json:
        print(f"Wrote summary JSON: {args.output_json}")


if __name__ == "__main__":
    main()
