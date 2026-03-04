#!/usr/bin/env python3
"""Decision-grade thermostability mutation design with bioactivity constraints.

This tool prioritizes mutation candidates for improved thermostability while
preserving activity by default.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from typing import Dict, Iterable, List, Set, Tuple

from Bio import SeqIO
from Bio.SeqUtils.ProtParam import ProteinAnalysis

VALID_AA = set("ACDEFGHIKLMNPQRSTVWY")
AMBIGUOUS_AA = set("BZXJUO")

AA_CLASS = {
    "A": "aliphatic",
    "V": "aliphatic",
    "L": "aliphatic",
    "I": "aliphatic",
    "M": "aliphatic",
    "F": "aromatic",
    "Y": "aromatic",
    "W": "aromatic",
    "S": "polar",
    "T": "polar",
    "N": "polar",
    "Q": "polar",
    "D": "acidic",
    "E": "acidic",
    "K": "basic",
    "R": "basic",
    "H": "basic",
    "G": "special",
    "P": "special",
    "C": "special",
}

MUTATION_RE = re.compile(r"^([A-Z])(\d+)([A-Z])$")


def normalize_sequence(seq: str) -> str:
    return seq.replace("\n", "").replace("\r", "").replace(" ", "").upper()


def validate_sequence(seq: str) -> Tuple[bool, bool]:
    invalid = sorted(set(seq) - VALID_AA - AMBIGUOUS_AA)
    if invalid:
        raise ValueError(f"Invalid residues: {''.join(invalid)}")
    has_ambiguous = bool(set(seq) & AMBIGUOUS_AA)
    return True, has_ambiguous


def read_fasta(path: str, record_id: str | None) -> Tuple[str, str]:
    parser = SeqIO.parse(path, "fasta")

    if record_id:
        for rec in parser:
            if rec.id == record_id or rec.name == record_id:
                return rec.id, str(rec.seq)
        raise ValueError(f"Record ID '{record_id}' not found in FASTA")

    first = next(parser, None)
    if first is None:
        raise ValueError("No FASTA records found")

    second = next(parser, None)
    if second is not None:
        print("Warning: multiple FASTA records found; using the first record.", file=sys.stderr)

    return first.id, str(first.seq)


def parse_positions(tokens: Iterable[str], max_pos: int) -> Set[int]:
    positions: Set[int] = set()
    for raw_token in tokens:
        token = raw_token.strip()
        if not token:
            continue
        if "-" in token:
            parts = token.split("-", 1)
            if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit():
                raise ValueError(f"Invalid position range: {token}")
            start = int(parts[0])
            end = int(parts[1])
            if start > end:
                raise ValueError(f"Invalid range (start > end): {token}")
            if start < 1 or end > max_pos:
                raise ValueError(f"Range out of bounds: {token} (valid 1..{max_pos})")
            for p in range(start, end + 1):
                positions.add(p)
        else:
            if not token.isdigit():
                raise ValueError(f"Invalid position token: {token}")
            pos = int(token)
            if pos < 1 or pos > max_pos:
                raise ValueError(f"Position out of bounds: {pos} (valid 1..{max_pos})")
            positions.add(pos)
    return positions


def parse_positions_text(text: str, max_pos: int) -> Set[int]:
    tokens = []
    for part in text.replace("\n", ",").split(","):
        p = part.strip()
        if p:
            tokens.append(p)
    return parse_positions(tokens, max_pos)


def parse_positions_file(path: str, max_pos: int) -> Set[int]:
    with open(path, "r", encoding="utf-8") as f:
        return parse_positions_text(f.read(), max_pos)


def parse_mutation(mutation: str, sequence: str) -> Tuple[str, int, str]:
    mutation = mutation.strip().upper()
    match = MUTATION_RE.match(mutation)
    if not match:
        raise ValueError(f"Invalid mutation format: {mutation}")

    wt, pos_str, mut = match.groups()
    if wt not in VALID_AA:
        raise ValueError(f"Wild-type residue must be canonical amino acid: {mutation}")
    if mut not in VALID_AA:
        raise ValueError(f"Mutant residue must be canonical amino acid: {mutation}")

    pos = int(pos_str)
    if pos < 1 or pos > len(sequence):
        raise ValueError(f"Position {pos} out of range (1..{len(sequence)})")

    if sequence[pos - 1] != wt:
        raise ValueError(f"Wild-type mismatch at {pos}: expected {sequence[pos - 1]}, got {wt}")
    if wt == mut:
        raise ValueError(f"No-op mutation is not allowed: {mutation}")

    return wt, pos, mut


def is_conservative_substitution(wt: str, mut: str) -> bool:
    return AA_CLASS.get(wt) == AA_CLASS.get(mut)


def predict_thermostability_score(sequence: str) -> Dict[str, object]:
    protein = ProteinAnalysis(sequence)
    aa_raw = protein.amino_acids_percent
    aa = {
        residue: (value / 100.0 if value > 1.0 else value)
        for residue, value in aa_raw.items()
    }

    thermo = {
        "E": 1.5,
        "K": 1.5,
        "R": 1.3,
        "I": 1.2,
        "V": 1.2,
        "P": 1.1,
    }
    destab = {
        "Q": -0.8,
        "N": -0.8,
        "C": -1.0,
        "M": -0.5,
    }

    score = sum(aa.get(k, 0) * w for k, w in thermo.items())
    score += sum(aa.get(k, 0) * w for k, w in destab.items())

    pi = protein.isoelectric_point()
    gravy = protein.gravy()

    charge_factor = 1.0 if 5.0 < pi < 9.0 else 0.8
    hydro_factor = 1.2 if -0.5 < gravy < 0.5 else 1.0

    final_score = score * charge_factor * hydro_factor

    return {
        "thermostability_score": final_score,
        "interpretation": "High" if final_score > 0.5 else "Moderate" if final_score > 0 else "Low",
        "factors": {
            "charged_content": aa.get("E", 0) + aa.get("K", 0) + aa.get("R", 0),
            "hydrophobic_core_content": aa.get("I", 0) + aa.get("V", 0) + aa.get("L", 0),
            "proline_content": aa.get("P", 0),
            "isoelectric_point": pi,
            "gravy": gravy,
        },
    }


def _segment_aggregation_score(segment: str) -> int:
    hydrophobic = set("FILVMWY")
    beta_forming = set("VIYFWT")
    hyd = sum(1 for aa in segment if aa in hydrophobic)
    beta = sum(1 for aa in segment if aa in beta_forming)
    return 1 if hyd >= 4 and beta >= 3 else 0


def analyze_aggregation_propensity(sequence: str, window: int = 6) -> List[Dict[str, object]]:
    hits: List[Dict[str, object]] = []
    if len(sequence) < window:
        return hits

    hydrophobic = set("FILVMWY")
    beta_forming = set("VIYFWT")

    for i in range(len(sequence) - window + 1):
        segment = sequence[i : i + window]
        hyd = sum(1 for aa in segment if aa in hydrophobic)
        beta = sum(1 for aa in segment if aa in beta_forming)

        if hyd >= 4 and beta >= 3:
            hits.append(
                {
                    "position_1based": i + 1,
                    "segment": segment,
                    "hydrophobic_count": hyd,
                    "beta_count": beta,
                    "score": hyd * 0.6 + beta * 0.4,
                }
            )

    return hits


def local_aggregation_delta(sequence: str, position0: int, new_aa: str, window: int = 6) -> int:
    if len(sequence) < window:
        return 0

    start_min = max(0, position0 - window + 1)
    start_max = min(position0, len(sequence) - window)
    if start_min > start_max:
        return 0

    wt_hits = 0
    mut_hits = 0
    mutant_seq = sequence[:position0] + new_aa + sequence[position0 + 1 :]

    for start in range(start_min, start_max + 1):
        wt_hits += _segment_aggregation_score(sequence[start : start + window])
        mut_hits += _segment_aggregation_score(mutant_seq[start : start + window])

    return mut_hits - wt_hits


def estimate_ddg_simple(wt_seq: str, position0: int, new_aa: str) -> Dict[str, object]:
    aa_stability = {
        "C": -1.5,
        "W": -1.0,
        "F": -0.8,
        "Y": -0.7,
        "I": -0.6,
        "L": -0.5,
        "V": -0.5,
        "M": -0.3,
        "A": 0.0,
        "G": 0.3,
        "T": 0.1,
        "S": 0.2,
        "P": 0.4,
        "H": 0.1,
        "N": 0.3,
        "Q": 0.3,
        "D": 0.5,
        "E": 0.5,
        "K": 0.6,
        "R": 0.7,
    }

    wt_aa = wt_seq[position0]
    ddg = aa_stability.get(new_aa, 0) - aa_stability.get(wt_aa, 0)

    context = wt_seq[max(0, position0 - 2) : min(len(wt_seq), position0 + 3)]
    context_hydro = sum(1 for aa in context if aa in "FILVMWY") / len(context)

    if context_hydro > 0.6:
        ddg *= 1.5

    interpretation = "Stabilizing" if ddg < -0.5 else "Destabilizing" if ddg > 0.5 else "Neutral"

    return {
        "mutation": f"{wt_aa}{position0 + 1}{new_aa}",
        "ddg_estimate": ddg,
        "interpretation": interpretation,
        "confidence": "Low (rule-based model)",
    }


def activity_risk_tier(wt: str, mut: str, conservative: bool, protected: bool) -> str:
    if protected:
        return "High"
    if not conservative:
        return "High"
    if wt in {"G", "P", "C"} or mut in {"G", "P", "C"}:
        return "Medium"
    return "Low"


def evaluate_requested_mutations(
    sequence: str,
    mutations: List[str],
    protected_positions: Set[int],
    enforce_conservative: bool,
    min_stabilizing_ddg: float,
    max_aggregation_delta: int,
) -> List[Dict[str, object]]:
    results: List[Dict[str, object]] = []

    for m in mutations:
        wt, pos, mut = parse_mutation(m, sequence)
        conservative = is_conservative_substitution(wt, mut)
        ddg_res = estimate_ddg_simple(sequence, pos - 1, mut)
        agg_delta = local_aggregation_delta(sequence, pos - 1, mut)

        reasons: List[str] = []
        if pos in protected_positions:
            reasons.append("protected_functional_residue")
        if enforce_conservative and not conservative:
            reasons.append("non_conservative_substitution")
        if ddg_res["ddg_estimate"] > min_stabilizing_ddg:
            reasons.append("insufficient_stability_gain")
        if agg_delta > max_aggregation_delta:
            reasons.append("aggregation_risk_increase")

        status = "Rejected" if reasons else "Pass"

        results.append(
            {
                "mutation": f"{wt}{pos}{mut}",
                "status": status,
                "reasons": reasons,
                "ddg_estimate": round(ddg_res["ddg_estimate"], 4),
                "aggregation_delta": agg_delta,
                "conservative": conservative,
                "activity_risk": activity_risk_tier(wt, mut, conservative, pos in protected_positions),
            }
        )

    return results


def design_candidates(
    sequence: str,
    protected_positions: Set[int],
    top_n: int,
    enforce_conservative: bool,
    min_stabilizing_ddg: float,
    max_aggregation_delta: int,
) -> Tuple[List[Dict[str, object]], Dict[str, int]]:
    candidates: List[Dict[str, object]] = []
    rejection = {
        "protected_position": 0,
        "non_conservative": 0,
        "insufficient_stability_gain": 0,
        "aggregation_risk_increase": 0,
    }

    for pos in range(1, len(sequence) + 1):
        wt = sequence[pos - 1]

        for mut in sorted(VALID_AA):
            if mut == wt:
                continue

            if pos in protected_positions:
                rejection["protected_position"] += 1
                continue

            conservative = is_conservative_substitution(wt, mut)
            if enforce_conservative and not conservative:
                rejection["non_conservative"] += 1
                continue

            ddg_res = estimate_ddg_simple(sequence, pos - 1, mut)
            ddg = float(ddg_res["ddg_estimate"])
            if ddg > min_stabilizing_ddg:
                rejection["insufficient_stability_gain"] += 1
                continue

            agg_delta = local_aggregation_delta(sequence, pos - 1, mut)
            if agg_delta > max_aggregation_delta:
                rejection["aggregation_risk_increase"] += 1
                continue

            risk = activity_risk_tier(wt, mut, conservative, False)
            risk_penalty = {"Low": 0.0, "Medium": 0.4, "High": 1.0}[risk]
            score = (-ddg) + (0.35 if conservative else 0.0) - (0.25 * agg_delta) - risk_penalty

            candidates.append(
                {
                    "mutation": f"{wt}{pos}{mut}",
                    "position_1based": pos,
                    "wt": wt,
                    "mut": mut,
                    "ddg_estimate": round(ddg, 4),
                    "aggregation_delta": agg_delta,
                    "conservative": conservative,
                    "activity_risk": risk,
                    "priority_score": round(score, 4),
                    "rationale": "stabilizing_ddg + no_agg_increase + activity_safe_filter",
                }
            )

    risk_rank = {"Low": 0, "Medium": 1, "High": 2}
    candidates.sort(
        key=lambda x: (risk_rank[x["activity_risk"]], -x["priority_score"], x["ddg_estimate"])
    )

    if top_n > 0:
        candidates = candidates[:top_n]

    return candidates, rejection


def format_report(
    record_id: str,
    sequence: str,
    ambiguous: bool,
    protected_positions: Set[int],
    enforce_protected: bool,
    evaluated_mutations: List[Dict[str, object]],
    designed_candidates: List[Dict[str, object]],
    rejection_summary: Dict[str, int],
) -> Tuple[str, Dict[str, object]]:
    protein = ProteinAnalysis(sequence)
    thermo = predict_thermostability_score(sequence)
    agg = analyze_aggregation_propensity(sequence)

    lines: List[str] = [
        "THERMOSTABLE MUTATION DESIGN REPORT",
        "=" * 72,
        f"Record ID: {record_id}",
        f"Length: {len(sequence)} aa",
        f"Molecular Weight: {protein.molecular_weight():.2f} Da",
        f"Isoelectric Point: {protein.isoelectric_point():.2f}",
        f"Aromaticity: {protein.aromaticity():.3f}",
        f"Instability Index: {protein.instability_index():.2f}",
        f"GRAVY: {protein.gravy():.3f}",
        "",
        "BASELINE THERMOSTABILITY (heuristic)",
        "-" * 72,
        f"Thermostability Score: {thermo['thermostability_score']:.3f} ({thermo['interpretation']})",
        f"Charged content (E+K+R): {thermo['factors']['charged_content'] * 100:.1f}%",
        f"Hydrophobic core (I+V+L): {thermo['factors']['hydrophobic_core_content'] * 100:.1f}%",
        f"Proline content: {thermo['factors']['proline_content'] * 100:.1f}%",
        "",
        "BIOACTIVITY-PRESERVING ENFORCEMENT",
        "-" * 72,
        f"Protected positions required/enforced: {'Yes' if enforce_protected else 'No (explicit override)'}",
        f"Protected positions count: {len(protected_positions)}",
        (
            "Protected positions: "
            + (", ".join(str(p) for p in sorted(protected_positions)) if protected_positions else "None")
        ),
        "",
        "AGGREGATION RISK (heuristic)",
        "-" * 72,
        f"High-risk windows detected: {len(agg)}",
    ]

    if ambiguous:
        lines.append("Warning: ambiguous residues detected; decision-grade confidence is reduced.")

    if agg:
        lines.append("Top aggregation-prone windows (1-based start):")
        for region in sorted(agg, key=lambda x: x["score"], reverse=True)[:5]:
            lines.append(
                f"  Pos {region['position_1based']:4d}: {region['segment']} (score={region['score']:.2f})"
            )

    if evaluated_mutations:
        lines.extend(["", "EVALUATED MUTATIONS", "-" * 72])
        for row in evaluated_mutations:
            reason_text = ",".join(row["reasons"]) if row["reasons"] else "pass"
            lines.append(
                f"{row['mutation']}: {row['status']} | ddG={row['ddg_estimate']:.2f} | "
                f"agg_delta={row['aggregation_delta']} | conservative={row['conservative']} | "
                f"risk={row['activity_risk']} | reasons={reason_text}"
            )

    if designed_candidates:
        lines.extend(["", "RANKED DESIGN CANDIDATES", "-" * 72])
        for row in designed_candidates:
            lines.append(
                f"{row['mutation']}: score={row['priority_score']:.2f} | ddG={row['ddg_estimate']:.2f} | "
                f"agg_delta={row['aggregation_delta']} | conservative={row['conservative']} | "
                f"risk={row['activity_risk']}"
            )

    if rejection_summary:
        lines.extend(["", "REJECTION SUMMARY", "-" * 72])
        for key, value in rejection_summary.items():
            lines.append(f"{key}: {value}")

    lines.extend(
        [
            "",
            "CONFIDENCE AND ESCALATION",
            "-" * 72,
            "This ranking is heuristic. Use structure-aware methods (FoldX/Rosetta/ML consensus)",
            "and wet-lab Tm/T50/activity assays before decision-critical use.",
        ]
    )

    data = {
        "record_id": record_id,
        "length": len(sequence),
        "molecular_weight": protein.molecular_weight(),
        "isoelectric_point": protein.isoelectric_point(),
        "aromaticity": protein.aromaticity(),
        "instability_index": protein.instability_index(),
        "gravy": protein.gravy(),
        "thermostability": thermo,
        "aggregation_hits": agg,
        "protected_positions": sorted(protected_positions),
        "enforce_protected": enforce_protected,
        "evaluated_mutations": evaluated_mutations,
        "design_candidates": designed_candidates,
        "rejection_summary": rejection_summary,
        "ambiguous_residues": ambiguous,
    }

    return "\n".join(lines) + "\n", data


def write_csv(path: str, rows: List[Dict[str, object]]) -> None:
    if not rows:
        return

    fieldnames = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def load_mutations_arg(mutations_arg: str | None, mutations_file: str | None) -> List[str]:
    mutations: List[str] = []
    if mutations_arg:
        mutations.extend([m.strip() for m in mutations_arg.split(",") if m.strip()])
    if mutations_file:
        with open(mutations_file, "r", encoding="utf-8") as f:
            mutations.extend([line.strip() for line in f if line.strip()])
    return mutations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decision-grade thermostability mutation design with bioactivity constraints.",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--fasta", help="Input FASTA file")
    group.add_argument("--sequence", help="Protein sequence (raw)")

    parser.add_argument("--record-id", help="FASTA record ID to use")
    parser.add_argument("--mutations", help="Comma-separated mutations, e.g., A123V,G45D")
    parser.add_argument("--mutations-file", help="Text file with one mutation per line")

    parser.add_argument(
        "--design-candidates",
        type=int,
        default=0,
        help="Number of ranked candidate mutations to design (0 disables design mode)",
    )
    parser.add_argument(
        "--protected-positions",
        help="Protected 1-based positions/ranges, e.g., 57,102,195-197",
    )
    parser.add_argument("--protected-positions-file", help="File containing protected positions/ranges")

    parser.add_argument(
        "--allow-missing-protected",
        action="store_true",
        help="Override safety gate and allow design mode without protected positions",
    )
    parser.add_argument(
        "--allow-nonconservative",
        action="store_true",
        help="Allow non-conservative substitutions in design/evaluation",
    )
    parser.add_argument(
        "--min-stabilizing-ddg",
        type=float,
        default=-0.3,
        help="Retain candidates with ddG <= threshold (default: -0.3)",
    )
    parser.add_argument(
        "--max-aggregation-delta",
        type=int,
        default=0,
        help="Retain candidates with local aggregation delta <= threshold (default: 0)",
    )

    parser.add_argument("--report", help="Write text report to file")
    parser.add_argument("--json", dest="json_path", help="Write JSON output to file")
    parser.add_argument("--evaluated-csv", help="Write evaluated mutations to CSV")
    parser.add_argument("--candidates-csv", help="Write designed candidates to CSV")

    args = parser.parse_args()

    try:
        if args.fasta:
            record_id, seq = read_fasta(args.fasta, args.record_id)
        else:
            record_id = args.record_id or "sequence"
            seq = args.sequence or ""

        seq = normalize_sequence(seq)
        _, ambiguous = validate_sequence(seq)

        if ambiguous and args.design_candidates > 0:
            raise ValueError(
                "Ambiguous residues detected. Decision-grade design mode requires canonical amino acids only."
            )

        protected_positions: Set[int] = set()
        if args.protected_positions:
            protected_positions |= parse_positions_text(args.protected_positions, len(seq))
        if args.protected_positions_file:
            protected_positions |= parse_positions_file(args.protected_positions_file, len(seq))

        enforce_protected = True
        if args.design_candidates > 0 and not protected_positions:
            if args.allow_missing_protected:
                enforce_protected = False
                print(
                    "Warning: running without protected positions due to explicit override.",
                    file=sys.stderr,
                )
            else:
                raise ValueError(
                    "Design mode requires protected functional positions by default. "
                    "Provide --protected-positions/--protected-positions-file or explicitly set "
                    "--allow-missing-protected."
                )

        mutations = load_mutations_arg(args.mutations, args.mutations_file)
        enforce_conservative = not args.allow_nonconservative

        evaluated_mutations = evaluate_requested_mutations(
            sequence=seq,
            mutations=mutations,
            protected_positions=protected_positions,
            enforce_conservative=enforce_conservative,
            min_stabilizing_ddg=args.min_stabilizing_ddg,
            max_aggregation_delta=args.max_aggregation_delta,
        )

        designed_candidates: List[Dict[str, object]] = []
        rejection_summary: Dict[str, int] = {}
        if args.design_candidates > 0:
            designed_candidates, rejection_summary = design_candidates(
                sequence=seq,
                protected_positions=protected_positions,
                top_n=args.design_candidates,
                enforce_conservative=enforce_conservative,
                min_stabilizing_ddg=args.min_stabilizing_ddg,
                max_aggregation_delta=args.max_aggregation_delta,
            )

        report_text, data = format_report(
            record_id=record_id,
            sequence=seq,
            ambiguous=ambiguous,
            protected_positions=protected_positions,
            enforce_protected=enforce_protected,
            evaluated_mutations=evaluated_mutations,
            designed_candidates=designed_candidates,
            rejection_summary=rejection_summary,
        )

        if args.report:
            with open(args.report, "w", encoding="utf-8") as f:
                f.write(report_text)
        else:
            print(report_text)

        if args.json_path:
            with open(args.json_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)

        if args.evaluated_csv:
            write_csv(args.evaluated_csv, evaluated_mutations)
        if args.candidates_csv:
            write_csv(args.candidates_csv, designed_candidates)

    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
