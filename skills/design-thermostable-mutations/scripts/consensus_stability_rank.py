#!/usr/bin/env python3
"""
Aggregate multiple stability metrics into a consensus mutant ranking.

Input CSV should contain one row per mutation candidate with columns for metrics.
By default, lower values are treated as better (typical DDG convention).
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def parse_list(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def normalize_minmax(values: list[float], higher_is_better: bool) -> list[float]:
    if not values:
        return []
    lo = min(values)
    hi = max(values)
    if hi == lo:
        return [0.5 for _ in values]
    if higher_is_better:
        return [(v - lo) / (hi - lo) for v in values]
    return [(hi - v) / (hi - lo) for v in values]


def normalize_rank(values: list[float], higher_is_better: bool) -> list[float]:
    if not values:
        return []
    if len(values) == 1:
        return [1.0]

    # Average-rank ties for deterministic, outlier-robust normalization.
    indexed = list(enumerate(values))
    indexed.sort(key=lambda x: x[1], reverse=higher_is_better)

    ranks = [0.0 for _ in values]
    i = 0
    while i < len(indexed):
        j = i
        while j + 1 < len(indexed) and math.isclose(indexed[j + 1][1], indexed[i][1]):
            j += 1
        avg_rank = (i + j) / 2.0
        for k in range(i, j + 1):
            ranks[indexed[k][0]] = avg_rank
        i = j + 1

    denom = len(values) - 1
    return [1.0 - (rank / denom) for rank in ranks]


def normalize(values: list[float], higher_is_better: bool, method: str) -> list[float]:
    if method == "rank":
        return normalize_rank(values, higher_is_better)
    return normalize_minmax(values, higher_is_better)


def read_rows_with_candidate_repair(path: str, candidate_column: str) -> tuple[list[str], list[dict[str, str]]]:
    with Path(path).open(newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration as exc:
            raise ValueError("Input CSV is empty.") from exc
        if candidate_column not in header:
            raise ValueError(f"Missing candidate column: {candidate_column}")
        expected = len(header)
        cand_idx = header.index(candidate_column)
        rows: list[dict[str, str]] = []

        for raw in reader:
            if not raw:
                continue
            if len(raw) < expected:
                raw = raw + ([""] * (expected - len(raw)))
            elif len(raw) > expected:
                overflow = len(raw) - expected
                # Recover common malformed input where multi-mutation IDs are not quoted.
                merged = ",".join(raw[cand_idx : cand_idx + overflow + 1])
                raw = raw[:cand_idx] + [merged] + raw[cand_idx + overflow + 1 :]
                if len(raw) != expected:
                    raw = raw[:expected] + ([""] * max(0, expected - len(raw)))
            rows.append(dict(zip(header, raw)))
    return header, rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Rank mutation candidates by consensus stability evidence.")
    parser.add_argument("--input", required=True, help="Input CSV with candidate rows.")
    parser.add_argument(
        "--metrics",
        required=True,
        help="Comma-separated metric columns to aggregate, e.g. foldx_ddg,rosetta_ddg.",
    )
    parser.add_argument(
        "--candidate-column",
        default="mutations",
        help="Column containing mutation IDs (default: mutations).",
    )
    parser.add_argument(
        "--weights",
        default="",
        help="Optional comma-separated metric weights aligned to --metrics.",
    )
    parser.add_argument(
        "--higher-is-better",
        default="",
        help="Comma-separated metric names where larger values are favorable.",
    )
    parser.add_argument(
        "--normalization",
        choices=["minmax", "rank"],
        default="minmax",
        help="Per-metric normalization approach (default: minmax).",
    )
    parser.add_argument(
        "--min-metrics",
        type=int,
        default=1,
        help="Require at least this many valid metrics per row (default: 1).",
    )
    parser.add_argument(
        "--strict-numeric",
        action="store_true",
        help="Fail if any selected metric contains non-numeric values.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output CSV path for consensus ranking.",
    )
    parser.add_argument(
        "--summary-json",
        help="Optional JSON summary path for ranking metadata and missingness stats.",
    )
    args = parser.parse_args()

    metrics = parse_list(args.metrics)
    if not metrics:
        raise ValueError("No metrics provided.")

    higher_better = set(parse_list(args.higher_is_better))
    unknown_higher_better = sorted(higher_better - set(metrics))
    if unknown_higher_better:
        raise ValueError(
            "--higher-is-better contains metrics not present in --metrics: "
            + ",".join(unknown_higher_better)
        )

    if args.weights:
        raw_weights = parse_list(args.weights)
        if len(raw_weights) != len(metrics):
            raise ValueError("--weights length must match --metrics length.")
        weights = [float(w) for w in raw_weights]
    else:
        weights = [1.0 for _ in metrics]
    if any(weight < 0 for weight in weights):
        raise ValueError("Weights must be non-negative.")
    total_weight = sum(weights)
    if total_weight <= 0:
        raise ValueError("Total weight must be > 0.")

    header, rows = read_rows_with_candidate_repair(args.input, args.candidate_column)
    if not rows:
        raise ValueError("Input CSV has no data rows.")
    missing_metrics = [metric for metric in metrics if metric not in header]
    if missing_metrics:
        raise ValueError(f"Missing metric columns: {', '.join(missing_metrics)}")

    metric_values_by_row: dict[str, list[float | None]] = {m: [] for m in metrics}
    non_numeric_counts = {m: 0 for m in metrics}
    for row in rows:
        for metric in metrics:
            raw_value = row.get(metric)
            parsed = parse_float(raw_value)
            if parsed is None and raw_value is not None and raw_value.strip():
                non_numeric_counts[metric] += 1
                if args.strict_numeric:
                    candidate_id = row.get(args.candidate_column, "<unknown>")
                    raise ValueError(
                        f"Non-numeric value in metric '{metric}' for candidate '{candidate_id}': {raw_value!r}"
                    )
            metric_values_by_row[metric].append(parsed)

    normalized_by_metric: dict[str, list[float | None]] = {}
    for metric in metrics:
        values = metric_values_by_row[metric]
        indexed = [(idx, val) for idx, val in enumerate(values) if val is not None]
        if not indexed:
            normalized_by_metric[metric] = [None for _ in values]
            continue
        valid_indices = [idx for idx, _ in indexed]
        valid_values = [val for _, val in indexed]
        norm = normalize(valid_values, higher_is_better=(metric in higher_better), method=args.normalization)
        mapped = [None for _ in values]
        for idx, score in zip(valid_indices, norm):
            mapped[idx] = score
        normalized_by_metric[metric] = mapped

    ranked_rows: list[dict[str, str]] = []
    for idx, row in enumerate(rows):
        weighted_sum = 0.0
        used_weight = 0.0
        used_metrics = 0
        used_metric_names: list[str] = []

        for metric, weight in zip(metrics, weights):
            score = normalized_by_metric[metric][idx]
            if score is None:
                continue
            weighted_sum += score * weight
            used_weight += weight
            used_metrics += 1
            used_metric_names.append(metric)

        if used_metrics < args.min_metrics:
            continue

        consensus = weighted_sum / used_weight if used_weight > 0 else 0.0
        support = used_weight / total_weight

        out = dict(row)
        out["consensus_score"] = f"{consensus:.6f}"
        out["support_fraction"] = f"{support:.6f}"
        out["metrics_used"] = str(used_metrics)
        out["support_metrics"] = ",".join(used_metric_names)
        ranked_rows.append(out)

    ranked_rows.sort(
        key=lambda r: (
            -float(r["consensus_score"]),
            -float(r["support_fraction"]),
            r.get(args.candidate_column, ""),
        )
    )

    if not ranked_rows:
        raise ValueError("No rows met the filtering criteria; adjust --min-metrics or input data.")

    output_fields = list(header) + [
        "consensus_score",
        "support_fraction",
        "metrics_used",
        "support_metrics",
        "rank",
    ]
    with Path(args.output).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=output_fields)
        writer.writeheader()
        for rank, row in enumerate(ranked_rows, start=1):
            row["rank"] = str(rank)
            writer.writerow(row)

    if args.summary_json:
        metric_missing = {
            metric: sum(1 for value in metric_values_by_row[metric] if value is None)
            for metric in metrics
        }
        payload = {
            "rows_input": len(rows),
            "rows_ranked": len(ranked_rows),
            "metrics": metrics,
            "weights": dict(zip(metrics, weights)),
            "higher_is_better": sorted(higher_better),
            "normalization": args.normalization,
            "min_metrics": args.min_metrics,
            "missing_or_invalid_counts": metric_missing,
            "non_numeric_counts": non_numeric_counts,
        }
        with Path(args.summary_json).open("w") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")

    print(f"Wrote {len(ranked_rows)} ranked candidates to {args.output}")
    if args.summary_json:
        print(f"Summary: {args.summary_json}")


if __name__ == "__main__":
    main()
