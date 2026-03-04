#!/usr/bin/env python3
"""
Run FoldX scoring in chunks and merge/rank outputs.

This wrapper calls run_foldx_batch.py repeatedly so long jobs can be resumed.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import subprocess
import sys
from pathlib import Path


def read_candidates(path: Path) -> list[str]:
    lines: list[str] = []
    for raw in path.read_text().splitlines():
        text = raw.strip()
        if not text or text.startswith("#"):
            continue
        lines.append(text)
    if not lines:
        raise ValueError(f"No candidates found in: {path}")
    return lines


def chunk_items(items: list[str], chunk_size: int) -> list[list[str]]:
    return [items[i : i + chunk_size] for i in range(0, len(items), chunk_size)]


def write_chunk_file(path: Path, items: list[str]) -> None:
    path.write_text("\n".join(items) + "\n")


def csv_row_count(path: Path) -> int:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        return sum(1 for _ in reader)


def load_chunk_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def normalize_extra_args(extra_args: list[str]) -> list[str]:
    def arg_key(arg: str) -> str:
        text = arg.strip()
        if text.startswith("--"):
            return text.split("=", 1)[0]
        return text

    selected: list[str] = []
    seen: set[str] = set()
    for arg in reversed(extra_args):
        key = arg_key(arg)
        if key in seen:
            continue
        seen.add(key)
        selected.append(arg)
    selected.reverse()
    return selected


def run_one_chunk(
    *,
    python_bin: str,
    runner_script: Path,
    structure: Path,
    mutations_file: Path,
    mapping_json: Path | None,
    foldx_binary: str,
    output_mutation_format: str,
    output_file: str,
    extra_args: list[str],
    output_csv: Path,
    output_json: Path,
    output_mutant_file: Path,
) -> None:
    cmd = [
        python_bin,
        str(runner_script),
        "--structure",
        str(structure),
        "--mutations-file",
        str(mutations_file),
        "--foldx-binary",
        foldx_binary,
        "--output-mutation-format",
        output_mutation_format,
        "--output-file",
        output_file,
        "--timeout-sec",
        "0",
        "--output-csv",
        str(output_csv),
        "--output-json",
        str(output_json),
        "--output-mutant-file",
        str(output_mutant_file),
    ]
    if mapping_json is not None:
        cmd.extend(["--mapping-json", str(mapping_json)])
    for arg in extra_args:
        cmd.append(f"--extra-arg={arg}")
    subprocess.run(cmd, check=True)


def merge_chunks(
    chunk_csvs: list[Path],
    merged_csv: Path,
    ranked_csv: Path,
) -> tuple[int, int]:
    all_rows: list[dict[str, str]] = []
    fieldnames: list[str] | None = None

    for path in chunk_csvs:
        with path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            if fieldnames is None:
                fieldnames = list(reader.fieldnames or [])
            rows = list(reader)
            all_rows.extend(rows)

    if not fieldnames:
        raise ValueError("No chunk rows available to merge.")

    with merged_csv.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_rows)

    ok_rows = [
        row
        for row in all_rows
        if row.get("status") == "ok" and row.get("foldx_ddg_kcal_per_mol")
    ]
    ok_rows.sort(
        key=lambda r: (
            float(r["foldx_ddg_kcal_per_mol"]),
            r.get("mutations", ""),
        )
    )

    ranked_fields = [
        "rank",
        "mutations",
        "foldx_mutations",
        "foldx_ddg_kcal_per_mol",
        "status",
    ]
    with ranked_csv.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=ranked_fields)
        writer.writeheader()
        for i, row in enumerate(ok_rows, start=1):
            out = {
                "rank": str(i),
                "mutations": row.get("mutations", ""),
                "foldx_mutations": row.get("foldx_mutations", ""),
                "foldx_ddg_kcal_per_mol": row.get("foldx_ddg_kcal_per_mol", ""),
                "status": row.get("status", ""),
            }
            writer.writerow(out)

    return len(all_rows), len(ok_rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run FoldX in chunked batches and merge results.")
    parser.add_argument("--mutations-file", required=True, help="Mutation list file (one candidate per line).")
    parser.add_argument("--structure", required=True, help="Structure PDB path.")
    parser.add_argument("--mapping-json", help="Optional mapping JSON from structure_residue_mapper.py.")
    parser.add_argument("--foldx-binary", required=True, help="FoldX binary path.")
    parser.add_argument(
        "--runner-script",
        default=str(Path(__file__).with_name("run_foldx_batch.py")),
        help="Path to run_foldx_batch.py (default: same folder).",
    )
    parser.add_argument("--python-bin", default=sys.executable, help="Python interpreter for runner script.")
    parser.add_argument("--chunk-size", type=int, default=120, help="Candidates per chunk (default: 120).")
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory for chunk inputs, chunk outputs, and merged results.",
    )
    parser.add_argument(
        "--output-mutation-format",
        choices=["chainposmut", "wtchainposmut"],
        default="wtchainposmut",
        help="FoldX mutation format (default: wtchainposmut).",
    )
    parser.add_argument(
        "--output-file",
        default="DifferencesBetweenModels.fxout",
        help="FoldX output file to parse inside temp dir.",
    )
    parser.add_argument(
        "--extra-arg",
        action="append",
        default=[],
        help="Extra FoldX arg (repeatable). If omitted, adds --numberOfRuns=1.",
    )
    parser.add_argument(
        "--force-rerun",
        action="store_true",
        help="Rerun chunks even if valid chunk CSV output already exists.",
    )
    args = parser.parse_args()

    mutations_file = Path(args.mutations_file).resolve()
    structure = Path(args.structure).resolve()
    mapping_json = Path(args.mapping_json).resolve() if args.mapping_json else None
    runner_script = Path(args.runner_script).resolve()
    output_dir = Path(args.output_dir).resolve()
    chunk_input_dir = output_dir / "chunks"
    chunk_output_dir = output_dir / "chunk_scores"
    chunk_input_dir.mkdir(parents=True, exist_ok=True)
    chunk_output_dir.mkdir(parents=True, exist_ok=True)

    extra_args = list(args.extra_arg)
    if not any(arg.strip().startswith("--numberOfRuns=") for arg in extra_args):
        extra_args.append("--numberOfRuns=1")
    # Keep only the last occurrence of each option key, e.g. --numberOfRuns.
    extra_args = normalize_extra_args(extra_args)

    candidates = read_candidates(mutations_file)
    chunks = chunk_items(candidates, args.chunk_size)
    n_chunks = len(chunks)
    width = max(4, int(math.log10(max(1, n_chunks))) + 1)
    print(f"Total candidates: {len(candidates)}")
    print(f"Chunk size: {args.chunk_size}")
    print(f"Chunks: {n_chunks}")

    chunk_csvs: list[Path] = []
    for idx, chunk in enumerate(chunks, start=1):
        tag = f"chunk_{idx:0{width}d}"
        chunk_file = chunk_input_dir / f"{tag}.txt"
        out_csv = chunk_output_dir / f"{tag}.csv"
        out_json = chunk_output_dir / f"{tag}.json"
        out_mutant = chunk_output_dir / f"{tag}.mutant.txt"
        chunk_csvs.append(out_csv)
        write_chunk_file(chunk_file, chunk)

        if not args.force_rerun and out_csv.exists():
            try:
                n_rows = csv_row_count(out_csv)
            except Exception:
                n_rows = -1
            if n_rows == len(chunk):
                print(f"[{idx}/{n_chunks}] skip {tag} (existing rows={n_rows})")
                continue

        print(f"[{idx}/{n_chunks}] run  {tag} (n={len(chunk)})")
        run_one_chunk(
            python_bin=args.python_bin,
            runner_script=runner_script,
            structure=structure,
            mutations_file=chunk_file,
            mapping_json=mapping_json,
            foldx_binary=args.foldx_binary,
            output_mutation_format=args.output_mutation_format,
            output_file=args.output_file,
            extra_args=extra_args,
            output_csv=out_csv,
            output_json=out_json,
            output_mutant_file=out_mutant,
        )
        n_rows = csv_row_count(out_csv)
        print(f"[{idx}/{n_chunks}] done {tag} (rows={n_rows})")

    merged_csv = output_dir / "foldx_scores.merged.csv"
    ranked_csv = output_dir / "foldx_scores.ranked.csv"
    rows_total, rows_ok = merge_chunks(chunk_csvs, merged_csv, ranked_csv)
    summary = {
        "mutations_file": str(mutations_file),
        "structure": str(structure),
        "mapping_json": str(mapping_json) if mapping_json else "",
        "foldx_binary": args.foldx_binary,
        "chunk_size": args.chunk_size,
        "extra_args": extra_args,
        "chunks": n_chunks,
        "rows_total": rows_total,
        "rows_ok": rows_ok,
        "merged_csv": str(merged_csv),
        "ranked_csv": str(ranked_csv),
    }
    summary_path = output_dir / "foldx_chunked.summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

    print(f"Merged CSV: {merged_csv}")
    print(f"Ranked CSV: {ranked_csv}")
    print(f"Summary: {summary_path}")
    print(f"Rows total: {rows_total} | Rows ok: {rows_ok}")


if __name__ == "__main__":
    main()
