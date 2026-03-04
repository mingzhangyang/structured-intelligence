#!/usr/bin/env python3
"""
Run FoldX BuildModel on a batch of mutation candidates with optional mapping support.

Mutation input format is sequence notation by default (e.g., A123V or A123V,L200I).
If numbering differs between FASTA and structure, pass --mapping-json from
structure_residue_mapper.py.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

MUT_RE = re.compile(r"^([A-Z])(\d+)([A-Z])$")
VALID_AA = set("ACDEFGHIKLMNPQRSTVWY")


def parse_candidate_line(line: str) -> list[str]:
    text = line.strip()
    if not text or text.startswith("#"):
        return []
    units = [item.strip().upper() for item in text.split(",") if item.strip()]
    for unit in units:
        match = MUT_RE.match(unit)
        if not match:
            raise ValueError(f"Invalid mutation unit: {unit!r}")
        wt, _, mut = match.groups()
        if wt not in VALID_AA or mut not in VALID_AA:
            raise ValueError(f"Mutation unit must use canonical amino acids: {unit!r}")
    return units


def read_candidates(path: str, candidate_column: str) -> list[str]:
    input_path = Path(path)
    if input_path.suffix.lower() == ".csv":
        with input_path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            if candidate_column not in (reader.fieldnames or []):
                raise ValueError(f"Missing candidate column '{candidate_column}' in {path}")
            rows = []
            for row in reader:
                value = (row.get(candidate_column) or "").strip()
                if not value:
                    continue
                rows.append(value)
            return rows

    lines: list[str] = []
    for raw in input_path.read_text().splitlines():
        units = parse_candidate_line(raw)
        if not units:
            continue
        lines.append(",".join(units))
    return lines


def load_mapping(path: str) -> dict[int, dict[str, str]]:
    data = json.loads(Path(path).read_text())
    mapping = data.get("sequence_to_structure")
    if not isinstance(mapping, list):
        raise ValueError("mapping JSON missing 'sequence_to_structure' list.")
    by_pos: dict[int, dict[str, str]] = {}
    for entry in mapping:
        if not isinstance(entry, dict):
            continue
        if not bool(entry.get("mapped", False)):
            continue
        pos = int(entry["seq_pos"])
        by_pos[pos] = {
            "chain": str(entry.get("chain", "")),
            "resnum": str(entry.get("resnum", "")),
            "icode": str(entry.get("icode", "")),
            "structure_aa": str(entry.get("structure_aa", "")),
        }
    return by_pos


def convert_unit(
    unit: str,
    *,
    default_chain: str,
    mapping: dict[int, dict[str, str]] | None,
    format_out: str,
    allow_insertion_codes: bool,
    validate_structure_aa: bool,
) -> str:
    match = MUT_RE.match(unit)
    if not match:
        raise ValueError(f"Invalid mutation unit: {unit!r}")
    wt, pos_text, mut = match.groups()
    pos = int(pos_text)

    chain = default_chain
    resnum = pos_text
    icode = ""
    structure_aa = wt
    if mapping is not None:
        if pos not in mapping:
            raise ValueError(f"Position {pos} not found in mapping.")
        item = mapping[pos]
        chain = item["chain"] or default_chain
        resnum = item["resnum"]
        icode = item["icode"]
        structure_aa = item.get("structure_aa", wt)
        if validate_structure_aa and structure_aa and structure_aa != wt:
            raise ValueError(
                f"WT mismatch at sequence position {pos}: mutation expects {wt}, structure mapping has {structure_aa}."
            )
        if icode and not allow_insertion_codes:
            raise ValueError(
                f"Insertion code found at sequence position {pos} ({resnum}{icode}). "
                "Use --allow-insertion-codes if your FoldX build accepts them."
            )
        if icode:
            resnum = f"{resnum}{icode}"

    if format_out == "chainposmut":
        return f"{chain}{resnum}{mut}"
    return f"{wt}{chain}{resnum}{mut}"


def candidate_to_foldx_line(
    candidate: str,
    *,
    default_chain: str,
    mapping: dict[int, dict[str, str]] | None,
    format_out: str,
    allow_insertion_codes: bool,
    validate_structure_aa: bool,
) -> tuple[str, str]:
    units = parse_candidate_line(candidate)
    converted = [
        convert_unit(
            unit,
            default_chain=default_chain,
            mapping=mapping,
            format_out=format_out,
            allow_insertion_codes=allow_insertion_codes,
            validate_structure_aa=validate_structure_aa,
        )
        for unit in units
    ]
    return ",".join(units), ",".join(converted) + ";"


def extract_ddgs(lines: list[str], expected: int, ddg_column: int) -> list[float]:
    ddgs: list[float] = []
    for line in lines:
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        tokens = text.split()
        # FoldX reports include banner/header lines that may contain numeric
        # tokens (e.g., "FoldX 5 (2011)"). Keep only per-model result rows.
        if not tokens or not tokens[0].lower().endswith(".pdb"):
            continue
        if len(tokens) <= ddg_column:
            continue
        try:
            ddgs.append(float(tokens[ddg_column]))
        except ValueError:
            continue
    if expected and len(ddgs) != expected:
        raise ValueError(
            f"FoldX result count mismatch: expected {expected}, parsed {len(ddgs)} from output."
        )
    return ddgs


def resolve_foldx_output_file(work_dir: Path, requested_name: str) -> Path:
    requested = work_dir / requested_name
    if requested.exists():
        return requested

    candidates = sorted(
        [
            path
            for path in work_dir.glob("*.fxout")
            if path.name.lower().startswith("dif")
        ]
    )
    if not candidates:
        raise FileNotFoundError(
            f"FoldX output file not found: {requested}. No Dif*.fxout files found in {work_dir}."
        )
    if len(candidates) == 1:
        return candidates[0]

    # Prefer canonical DifferencesBetweenModels naming if present.
    for path in candidates:
        name = path.name.lower()
        if "differencesbetweenmodels" in name:
            return path
    return candidates[0]


def main() -> None:
    parser = argparse.ArgumentParser(description="Run FoldX batch mutation scoring.")
    parser.add_argument("--structure", required=True, help="Input PDB path.")
    parser.add_argument(
        "--mutations-file",
        required=True,
        help="Mutation candidates .txt (one candidate/line) or .csv with candidate column.",
    )
    parser.add_argument(
        "--candidate-column",
        default="mutations",
        help="Candidate column for CSV mutation input (default: mutations).",
    )
    parser.add_argument("--mapping-json", help="Optional mapping JSON from structure_residue_mapper.py.")
    parser.add_argument("--chain", default="A", help="Default chain when mapping is absent (default: A).")
    parser.add_argument(
        "--output-mutation-format",
        choices=["chainposmut", "wtchainposmut"],
        default="wtchainposmut",
        help="FoldX mutation encoding to write to mutant file (default: wtchainposmut).",
    )
    parser.add_argument(
        "--allow-insertion-codes",
        action="store_true",
        help="Allow residue insertion codes in mapped residue numbers.",
    )
    parser.add_argument(
        "--no-validate-structure-aa",
        action="store_true",
        help="Disable WT residue cross-check against mapping structure amino acid.",
    )
    parser.add_argument("--foldx-binary", default="foldx", help="FoldX binary path (default: foldx).")
    parser.add_argument("--command", default="BuildModel", help="FoldX command (default: BuildModel).")
    parser.add_argument(
        "--output-file",
        default="DifferencesBetweenModels.fxout",
        help="FoldX output file to parse (default: DifferencesBetweenModels.fxout).",
    )
    parser.add_argument(
        "--ddg-column",
        type=int,
        default=1,
        help="0-based numeric column in FoldX output for DDG (default: 1).",
    )
    parser.add_argument(
        "--extra-arg",
        action="append",
        default=[],
        help="Extra FoldX argument, repeatable, e.g. --extra-arg=--numberOfRuns=3",
    )
    parser.add_argument("--timeout-sec", type=int, default=0, help="Timeout in seconds (0 disables timeout).")
    parser.add_argument("--dry-run", action="store_true", help="Write mutant file and command only, do not execute.")
    parser.add_argument(
        "--output-csv",
        required=True,
        help="Output CSV path with foldx_ddg values (or status in dry-run mode).",
    )
    parser.add_argument("--output-json", help="Optional metadata JSON output.")
    parser.add_argument(
        "--output-mutant-file",
        help="Optional copy of generated FoldX mutant list file.",
    )
    args = parser.parse_args()

    structure_path = Path(args.structure).resolve()
    if not structure_path.exists():
        raise FileNotFoundError(f"Structure not found: {structure_path}")
    candidates = read_candidates(args.mutations_file, args.candidate_column)
    if not candidates:
        raise ValueError("No mutation candidates were found.")

    mapping = load_mapping(args.mapping_json) if args.mapping_json else None
    converted_rows: list[dict[str, str]] = []
    for candidate in candidates:
        original, foldx_line = candidate_to_foldx_line(
            candidate,
            default_chain=args.chain.upper(),
            mapping=mapping,
            format_out=args.output_mutation_format,
            allow_insertion_codes=args.allow_insertion_codes,
            validate_structure_aa=(not args.no_validate_structure_aa),
        )
        converted_rows.append({"mutations": original, "foldx_line": foldx_line})

    with tempfile.TemporaryDirectory(prefix="skill_foldx_") as tmpdir:
        tmpdir_path = Path(tmpdir)
        structure_copy = tmpdir_path / structure_path.name
        shutil.copy2(structure_path, structure_copy)

        # FoldX 5 may reject mutation files unless the basename starts with
        # "individual_list" or "mutant_file".
        mutant_file = tmpdir_path / "individual_list.txt"
        mutant_file.write_text("\n".join(item["foldx_line"] for item in converted_rows) + "\n")

        cmd = [
            args.foldx_binary,
            f"--command={args.command}",
            f"--pdb={structure_copy.name}",
            f"--mutant-file={mutant_file.name}",
        ]
        cmd.extend(args.extra_arg)
        cmd_text = " ".join(cmd)

        if args.output_mutant_file:
            Path(args.output_mutant_file).write_text(mutant_file.read_text())

        rows_out: list[dict[str, object]] = []
        if args.dry_run:
            for item in converted_rows:
                rows_out.append(
                    {
                        "mutations": item["mutations"],
                        "foldx_mutations": item["foldx_line"].rstrip(";"),
                        "foldx_ddg_kcal_per_mol": "",
                        "status": "dry_run",
                    }
                )
            stdout = ""
            stderr = ""
            return_code = 0
        else:
            result = subprocess.run(
                cmd,
                cwd=tmpdir_path,
                capture_output=True,
                text=True,
                check=False,
                timeout=(None if args.timeout_sec <= 0 else args.timeout_sec),
            )
            stdout = result.stdout or ""
            stderr = result.stderr or ""
            return_code = result.returncode
            if result.returncode != 0:
                raise RuntimeError(
                    f"FoldX failed with exit code {result.returncode}. "
                    f"stdout={stdout[:800]!r} stderr={stderr[:800]!r}"
                )

            output_path = resolve_foldx_output_file(tmpdir_path, args.output_file)
            ddgs = extract_ddgs(
                output_path.read_text(errors="replace").splitlines(),
                expected=len(converted_rows),
                ddg_column=args.ddg_column,
            )
            for item, ddg in zip(converted_rows, ddgs):
                rows_out.append(
                    {
                        "mutations": item["mutations"],
                        "foldx_mutations": item["foldx_line"].rstrip(";"),
                        "foldx_ddg_kcal_per_mol": f"{ddg:.6f}",
                        "status": "ok",
                    }
                )

    with Path(args.output_csv).open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["mutations", "foldx_mutations", "foldx_ddg_kcal_per_mol", "status"],
        )
        writer.writeheader()
        for row in rows_out:
            writer.writerow(row)

    if args.output_json:
        payload = {
            "structure": str(structure_path),
            "mutations_file": str(Path(args.mutations_file).resolve()),
            "n_candidates": len(candidates),
            "mapping_json": str(Path(args.mapping_json).resolve()) if args.mapping_json else "",
            "command": cmd_text,
            "dry_run": args.dry_run,
            "return_code": return_code,
            "resolved_output_file": (str(output_path.name) if not args.dry_run else ""),
            "stdout_preview": stdout[:1000],
            "stderr_preview": stderr[:1000],
            "output_csv": str(Path(args.output_csv).resolve()),
        }
        with Path(args.output_json).open("w") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")

    print(f"Wrote {len(rows_out)} rows to {args.output_csv}")
    if args.output_json:
        print(f"JSON: {args.output_json}")


if __name__ == "__main__":
    main()
