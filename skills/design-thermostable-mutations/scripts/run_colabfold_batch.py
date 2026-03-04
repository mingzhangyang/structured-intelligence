#!/usr/bin/env python3
"""
Run (or summarize) ColabFold batch predictions for WT/mutant FASTA libraries.

This wrapper standardizes command invocation and score aggregation. It does not
treat AF confidence as direct stability.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from pathlib import Path


def read_fasta_ids(path: str) -> list[str]:
    ids: list[str] = []
    for line in Path(path).read_text().splitlines():
        text = line.strip()
        if text.startswith(">"):
            ids.append(text[1:].split()[0])
    return ids


def _to_float(value: object) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            return float(text)
        except ValueError:
            return None
    return None


def _mean(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def extract_seq_id_from_score_filename(path: Path) -> str:
    stem = path.stem
    if "_scores_" in stem:
        return stem.split("_scores_", 1)[0]
    if "_rank_" in stem:
        return stem.split("_rank_", 1)[0]
    return stem


def collect_scores(output_dir: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for json_path in sorted(Path(output_dir).rglob("*.json")):
        name = json_path.name
        if "ranking_debug" in name:
            continue
        try:
            payload = json.loads(json_path.read_text())
        except Exception:
            continue
        if not isinstance(payload, dict):
            continue

        seq_id = extract_seq_id_from_score_filename(json_path)
        plddt_values: list[float] = []
        if isinstance(payload.get("plddt"), list):
            plddt_values = [float(x) for x in payload["plddt"] if isinstance(x, (int, float))]

        row = {
            "sequence_id": seq_id,
            "score_json": str(json_path),
            "model_name": str(payload.get("model", "")),
            "ranking_confidence": _to_float(payload.get("ranking_confidence")),
            "ptm": _to_float(payload.get("ptm")),
            "iptm": _to_float(payload.get("iptm")),
            "mean_plddt": _mean(plddt_values),
        }
        if any(row[k] is not None for k in ("ranking_confidence", "ptm", "iptm", "mean_plddt")):
            rows.append(row)
    return rows


def choose_best_by_sequence(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    by_id: dict[str, list[dict[str, object]]] = {}
    for row in rows:
        seq_id = str(row["sequence_id"])
        by_id.setdefault(seq_id, []).append(row)

    best: list[dict[str, object]] = []
    for seq_id, items in sorted(by_id.items()):
        def rank_key(item: dict[str, object]) -> tuple[float, float]:
            rc = item.get("ranking_confidence")
            mp = item.get("mean_plddt")
            return (
                float(rc) if isinstance(rc, (int, float)) else -1.0,
                float(mp) if isinstance(mp, (int, float)) else -1.0,
            )

        top = max(items, key=rank_key)
        entry = dict(top)
        entry["n_score_files"] = len(items)
        best.append(entry)
    return best


def write_all_scores(path: str, rows: list[dict[str, object]]) -> None:
    fields = [
        "sequence_id",
        "score_json",
        "model_name",
        "ranking_confidence",
        "ptm",
        "iptm",
        "mean_plddt",
    ]
    with Path(path).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_summary(path: str, rows: list[dict[str, object]], expected_ids: list[str]) -> None:
    fields = [
        "sequence_id",
        "status",
        "n_score_files",
        "ranking_confidence",
        "ptm",
        "iptm",
        "mean_plddt",
        "model_name",
        "score_json",
        "stability_note",
    ]
    by_id = {str(row["sequence_id"]): row for row in rows}
    with Path(path).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for seq_id in expected_ids:
            row = by_id.get(seq_id)
            if row is None:
                writer.writerow(
                    {
                        "sequence_id": seq_id,
                        "status": "missing_score_json",
                        "n_score_files": 0,
                        "stability_note": "AF confidence is structural confidence, not DDG.",
                    }
                )
                continue
            out = dict(row)
            out["status"] = "ok"
            out["stability_note"] = "AF confidence is structural confidence, not DDG."
            writer.writerow(out)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run or summarize ColabFold batch predictions.")
    parser.add_argument("--input-fasta", help="Input FASTA with WT/mutant sequences.")
    parser.add_argument("--output-dir", required=True, help="ColabFold output directory.")
    parser.add_argument("--binary", default="colabfold_batch", help="colabfold_batch binary path.")
    parser.add_argument("--model-type", help="Optional ColabFold --model-type value.")
    parser.add_argument("--msa-mode", help="Optional ColabFold --msa-mode value.")
    parser.add_argument("--pair-mode", help="Optional ColabFold --pair-mode value.")
    parser.add_argument("--num-recycle", type=int, help="Optional ColabFold --num-recycle.")
    parser.add_argument("--num-models", type=int, help="Optional ColabFold --num-models.")
    parser.add_argument("--amber", action="store_true", help="Enable ColabFold --amber.")
    parser.add_argument(
        "--extra-arg",
        action="append",
        default=[],
        help="Additional raw argument passed to colabfold_batch (repeatable).",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print command and skip execution.")
    parser.add_argument(
        "--collect-only",
        action="store_true",
        help="Skip execution and only summarize existing output directory.",
    )
    parser.add_argument(
        "--all-scores-csv",
        help="Optional output CSV containing one row per detected score JSON file.",
    )
    parser.add_argument(
        "--summary-csv",
        required=True,
        help="Summary CSV output (best score row per sequence ID).",
    )
    parser.add_argument("--summary-json", help="Optional summary metadata JSON output.")
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    command: list[str] = []
    run_performed = False
    stdout = ""
    stderr = ""
    return_code = 0

    if not args.collect_only:
        if not args.input_fasta:
            raise ValueError("--input-fasta is required unless --collect-only is set.")
        input_fasta = Path(args.input_fasta).resolve()
        if not input_fasta.exists():
            raise FileNotFoundError(f"Input FASTA not found: {input_fasta}")

        command = [args.binary]
        if args.model_type:
            command.append(f"--model-type={args.model_type}")
        if args.msa_mode:
            command.append(f"--msa-mode={args.msa_mode}")
        if args.pair_mode:
            command.append(f"--pair-mode={args.pair_mode}")
        if args.num_recycle is not None:
            command.append(f"--num-recycle={args.num_recycle}")
        if args.num_models is not None:
            command.append(f"--num-models={args.num_models}")
        if args.amber:
            command.append("--amber")
        command.extend(args.extra_arg)
        command.extend([str(input_fasta), str(output_dir)])

        if args.dry_run:
            print("Dry-run command:")
            print(" ".join(command))
        else:
            run_performed = True
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            stdout = result.stdout or ""
            stderr = result.stderr or ""
            return_code = result.returncode
            if result.returncode != 0:
                raise RuntimeError(
                    f"colabfold_batch failed with exit code {result.returncode}. "
                    f"stdout={stdout[:800]!r} stderr={stderr[:800]!r}"
                )

    if args.input_fasta:
        expected_ids = read_fasta_ids(args.input_fasta)
    else:
        expected_ids = sorted(
            {
                extract_seq_id_from_score_filename(path)
                for path in output_dir.rglob("*scores*.json")
            }
        )

    all_rows = collect_scores(str(output_dir))
    best_rows = choose_best_by_sequence(all_rows)

    if args.all_scores_csv:
        write_all_scores(args.all_scores_csv, all_rows)
    write_summary(args.summary_csv, best_rows, expected_ids)

    if args.summary_json:
        payload = {
            "output_dir": str(output_dir),
            "collect_only": args.collect_only,
            "dry_run": args.dry_run,
            "run_performed": run_performed,
            "return_code": return_code,
            "n_sequences_expected": len(expected_ids),
            "n_score_rows_detected": len(all_rows),
            "n_sequences_with_scores": len(best_rows),
            "summary_csv": str(Path(args.summary_csv).resolve()),
            "all_scores_csv": str(Path(args.all_scores_csv).resolve()) if args.all_scores_csv else "",
            "command": command,
            "stdout_preview": stdout[:1000],
            "stderr_preview": stderr[:1000],
        }
        with Path(args.summary_json).open("w") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")

    print(f"Summary CSV: {args.summary_csv}")
    if args.all_scores_csv:
        print(f"All scores CSV: {args.all_scores_csv}")
    if args.summary_json:
        print(f"Summary JSON: {args.summary_json}")


if __name__ == "__main__":
    main()
