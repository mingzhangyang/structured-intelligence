#!/usr/bin/env python3
"""
Run a decision-grade thermostability mutation design workflow end-to-end.

Default pipeline:
1) discover_candidate_sites.py
2) generate_mutation_library.py

Optional stages:
3) structure_residue_mapper.py (requires --structure)
4) run_foldx_batch.py (requires --run-foldx and --structure)
5) consensus_stability_rank.py (requires --run-consensus and --run-foldx)
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


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


def encode_positions(positions: set[int]) -> str:
    ordered = sorted(positions)
    if not ordered:
        return ""
    ranges: list[str] = []
    start = ordered[0]
    prev = ordered[0]
    for pos in ordered[1:]:
        if pos == prev + 1:
            prev = pos
            continue
        if start == prev:
            ranges.append(str(start))
        else:
            ranges.append(f"{start}-{prev}")
        start = pos
        prev = pos
    if start == prev:
        ranges.append(str(start))
    else:
        ranges.append(f"{start}-{prev}")
    return ",".join(ranges)


def add_arg(cmd: list[str], flag: str, value: str | None) -> None:
    if value is None:
        return
    text = str(value).strip()
    if not text:
        return
    cmd.extend([flag, text])


def run_step(step_name: str, cmd: list[str], dry_run: bool) -> dict[str, object]:
    started = datetime.now(timezone.utc)
    cmd_text = " ".join(shlex.quote(part) for part in cmd)
    print(f"[run] {step_name}: {cmd_text}")
    if dry_run:
        return {
            "step": step_name,
            "started_at_utc": started.isoformat(),
            "finished_at_utc": datetime.now(timezone.utc).isoformat(),
            "duration_seconds": 0.0,
            "status": "dry_run",
            "return_code": 0,
            "command": cmd,
            "command_text": cmd_text,
            "stdout_preview": "",
            "stderr_preview": "",
        }

    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    finished = datetime.now(timezone.utc)
    record = {
        "step": step_name,
        "started_at_utc": started.isoformat(),
        "finished_at_utc": finished.isoformat(),
        "duration_seconds": round((finished - started).total_seconds(), 3),
        "status": ("ok" if result.returncode == 0 else "failed"),
        "return_code": result.returncode,
        "command": cmd,
        "command_text": cmd_text,
        "stdout_preview": (result.stdout or "")[:4000],
        "stderr_preview": (result.stderr or "")[:4000],
    }
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr)
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description="Run decision-grade thermostability mutation design pipeline.")
    parser.add_argument("--sequence-fasta", required=True, help="WT FASTA.")
    parser.add_argument(
        "--output-dir",
        default="",
        help="Output directory (default: ./pipeline_runs/<timestamp>).",
    )
    parser.add_argument(
        "--objective",
        default="mixed",
        choices=["mixed", "thermostability", "ph-tolerance", "solvent-tolerance"],
        help="Primary design objective.",
    )
    parser.add_argument("--structure", help="Optional structure (.pdb/.cif/.mmcif).")
    parser.add_argument("--chain", help="Optional chain id.")
    parser.add_argument("--top-n", type=int, default=30, help="Top discovered sites to keep (default: 30).")
    parser.add_argument(
        "--max-targets-per-site",
        type=int,
        default=8,
        help="Max target substitutions per discovered site.",
    )
    parser.add_argument(
        "--include-blocked",
        action="store_true",
        help="Include blocked sites in discover selected list.",
    )

    parser.add_argument("--active-site", default="", help="Comma/range catalytic positions.")
    parser.add_argument("--cofactor-sites", default="", help="Comma/range cofactor-contact positions.")
    parser.add_argument("--disulfide-sites", default="", help="Comma/range disulfide-related positions.")
    parser.add_argument("--interface-sites", default="", help="Comma/range interface-sensitive positions.")
    parser.add_argument("--conserved-sites", default="", help="Comma/range conserved positions.")
    parser.add_argument("--blocklist-sites", default="", help="Comma/range blocked positions.")
    parser.add_argument("--prefer-sites", default="", help="Comma/range preferred positions.")
    parser.add_argument("--active-site-file", help="File with active-site positions.")
    parser.add_argument("--cofactor-sites-file", help="File with cofactor-site positions.")
    parser.add_argument("--disulfide-sites-file", help="File with disulfide-site positions.")
    parser.add_argument("--interface-sites-file", help="File with interface-site positions.")
    parser.add_argument("--conserved-sites-file", help="File with conserved-site positions.")
    parser.add_argument("--blocklist-sites-file", help="File with blocked positions.")
    parser.add_argument("--prefer-sites-file", help="File with preferred positions.")
    parser.add_argument(
        "--allow-missing-functional-constraints",
        action="store_true",
        help="Allow running discovery without active/cofactor/disulfide/blocklist positions.",
    )
    parser.add_argument(
        "--allow-functional-sites",
        action="store_true",
        help="Allow scoring functional positions with penalty.",
    )

    parser.add_argument("--max-mutations", type=int, default=2, help="Max substitutions per library candidate.")
    parser.add_argument("--max-candidates", type=int, default=5000, help="Hard cap for candidate count.")
    parser.add_argument("--include-wt-target", action="store_true", help="Allow WT residue in target set.")
    parser.add_argument("--disallow", default="CP", help="Disallow target residues (default: CP).")
    parser.add_argument(
        "--allow-duplicate-sequences",
        action="store_true",
        help="Keep duplicate-by-sequence candidates.",
    )

    parser.add_argument("--protected-sites", default="", help="Comma/range protected positions.")
    parser.add_argument("--protected-sites-file", help="File with protected positions.")
    parser.add_argument(
        "--allow-missing-protected",
        action="store_true",
        help="Allow library generation without protected positions.",
    )
    parser.add_argument(
        "--allow-protected-sites",
        action="store_true",
        help="Allow mutagenesis at protected positions.",
    )
    parser.add_argument(
        "--include-conserved-in-protected",
        action="store_true",
        help="Include conserved positions in auto-derived protected set.",
    )
    parser.add_argument(
        "--include-interface-in-protected",
        action="store_true",
        help="Include interface-sensitive positions in auto-derived protected set.",
    )

    parser.add_argument(
        "--mapping-strict",
        action="store_true",
        help="Require sequence/structure identity and coverage thresholds in mapping step.",
    )
    parser.add_argument("--mapping-min-identity", type=float, default=0.5, help="Mapper min identity threshold.")
    parser.add_argument("--mapping-min-coverage", type=float, default=0.7, help="Mapper min coverage threshold.")

    parser.add_argument("--run-foldx", action="store_true", help="Run FoldX batch scoring.")
    parser.add_argument("--foldx-binary", default="foldx", help="FoldX binary path.")
    parser.add_argument(
        "--foldx-output-mutation-format",
        choices=["chainposmut", "wtchainposmut"],
        default="wtchainposmut",
        help="FoldX mutation format.",
    )
    parser.add_argument("--foldx-chain", default="A", help="Default FoldX chain when mapping is absent.")
    parser.add_argument("--foldx-output-file", default="DifferencesBetweenModels.fxout", help="FoldX output file.")
    parser.add_argument("--foldx-ddg-column", type=int, default=1, help="FoldX DDG column index.")
    parser.add_argument(
        "--foldx-extra-arg",
        action="append",
        default=[],
        help="Extra FoldX arg, repeatable. Example: --foldx-extra-arg=--numberOfRuns=3",
    )
    parser.add_argument("--foldx-timeout-sec", type=int, default=0, help="FoldX timeout in seconds.")
    parser.add_argument("--foldx-dry-run", action="store_true", help="Write FoldX inputs but do not execute FoldX.")
    parser.add_argument(
        "--foldx-allow-insertion-codes",
        action="store_true",
        help="Allow insertion codes in FoldX mapping conversion.",
    )
    parser.add_argument(
        "--foldx-no-validate-structure-aa",
        action="store_true",
        help="Disable WT residue validation against mapping structure aa.",
    )

    parser.add_argument("--run-consensus", action="store_true", help="Run consensus ranking after FoldX.")
    parser.add_argument("--consensus-metrics", default="foldx_ddg_kcal_per_mol", help="Consensus metric columns.")
    parser.add_argument("--consensus-weights", default="", help="Optional metric weights.")
    parser.add_argument("--consensus-higher-is-better", default="", help="Metrics where larger is better.")
    parser.add_argument(
        "--consensus-normalization",
        choices=["minmax", "rank"],
        default="rank",
        help="Consensus normalization method (default: rank).",
    )
    parser.add_argument("--consensus-min-metrics", type=int, default=1, help="Minimum valid metrics per candidate.")
    parser.add_argument(
        "--consensus-strict-numeric",
        action="store_true",
        help="Fail if consensus metrics contain non-numeric values.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print commands and write manifest without execution.")
    args = parser.parse_args()

    if args.run_foldx and not args.structure:
        raise ValueError("--run-foldx requires --structure.")
    if args.run_consensus and not args.run_foldx:
        raise ValueError("--run-consensus requires --run-foldx.")
    if args.run_consensus and args.foldx_dry_run and not args.dry_run:
        raise ValueError("--run-consensus cannot be combined with --foldx-dry-run.")

    now_tag = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_dir = (
        Path(args.output_dir).resolve()
        if args.output_dir
        else (Path.cwd() / "pipeline_runs" / f"decision_pipeline_{now_tag}").resolve()
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    script_dir = Path(__file__).resolve().parent
    discover_script = script_dir / "discover_candidate_sites.py"
    library_script = script_dir / "generate_mutation_library.py"
    mapper_script = script_dir / "structure_residue_mapper.py"
    foldx_script = script_dir / "run_foldx_batch.py"
    consensus_script = script_dir / "consensus_stability_rank.py"
    for script in (discover_script, library_script, mapper_script, foldx_script, consensus_script):
        if not script.exists():
            raise FileNotFoundError(f"Missing required script: {script}")

    out_paths: dict[str, str] = {
        "output_dir": str(output_dir),
        "discover_csv": str(output_dir / "01_site_candidates.csv"),
        "discover_json": str(output_dir / "01_site_summary.json"),
        "site_specs": str(output_dir / "01_site_specs.txt"),
        "library_csv": str(output_dir / "02_mutation_library.csv"),
        "library_fasta": str(output_dir / "02_mutation_library.fasta"),
        "library_list": str(output_dir / "02_mutation_candidates.txt"),
        "library_metadata_json": str(output_dir / "02_library_metadata.json"),
        "mapping_json": str(output_dir / "03_sequence_structure_mapping.json"),
        "mapping_tsv": str(output_dir / "03_sequence_structure_mapping.tsv"),
        "foldx_csv": str(output_dir / "04_foldx_scores.csv"),
        "foldx_json": str(output_dir / "04_foldx_metadata.json"),
        "consensus_csv": str(output_dir / "05_consensus_ranking.csv"),
        "consensus_json": str(output_dir / "05_consensus_summary.json"),
        "manifest_json": str(output_dir / "pipeline_manifest.json"),
    }

    functional_constraints = {
        "active_sites": sorted(load_position_set(args.active_site, args.active_site_file)),
        "cofactor_sites": sorted(load_position_set(args.cofactor_sites, args.cofactor_sites_file)),
        "disulfide_sites": sorted(load_position_set(args.disulfide_sites, args.disulfide_sites_file)),
        "blocklist_sites": sorted(load_position_set(args.blocklist_sites, args.blocklist_sites_file)),
        "conserved_sites": sorted(load_position_set(args.conserved_sites, args.conserved_sites_file)),
        "interface_sites": sorted(load_position_set(args.interface_sites, args.interface_sites_file)),
    }

    protected_sites = load_position_set(args.protected_sites, args.protected_sites_file)
    derived_protected_sources: dict[str, list[int]] = {}
    if not protected_sites:
        derived_protected_sources = {
            "active_sites": functional_constraints["active_sites"],
            "cofactor_sites": functional_constraints["cofactor_sites"],
            "disulfide_sites": functional_constraints["disulfide_sites"],
            "blocklist_sites": functional_constraints["blocklist_sites"],
        }
        if args.include_conserved_in_protected:
            derived_protected_sources["conserved_sites"] = functional_constraints["conserved_sites"]
        if args.include_interface_in_protected:
            derived_protected_sources["interface_sites"] = functional_constraints["interface_sites"]
        for values in derived_protected_sources.values():
            protected_sites |= set(values)

    steps: list[dict[str, object]] = []
    failure = ""
    started_at = datetime.now(timezone.utc)

    try:
        discover_cmd = [
            sys.executable,
            str(discover_script),
            "--sequence-fasta",
            str(Path(args.sequence_fasta).resolve()),
            "--objective",
            args.objective,
            "--top-n",
            str(args.top_n),
            "--max-targets-per-site",
            str(args.max_targets_per_site),
            "--output-csv",
            out_paths["discover_csv"],
            "--output-json",
            out_paths["discover_json"],
            "--output-site-specs",
            out_paths["site_specs"],
        ]
        add_arg(discover_cmd, "--structure", (str(Path(args.structure).resolve()) if args.structure else None))
        add_arg(discover_cmd, "--chain", args.chain)
        add_arg(discover_cmd, "--active-site", args.active_site)
        add_arg(discover_cmd, "--cofactor-sites", args.cofactor_sites)
        add_arg(discover_cmd, "--disulfide-sites", args.disulfide_sites)
        add_arg(discover_cmd, "--interface-sites", args.interface_sites)
        add_arg(discover_cmd, "--conserved-sites", args.conserved_sites)
        add_arg(discover_cmd, "--blocklist-sites", args.blocklist_sites)
        add_arg(discover_cmd, "--prefer-sites", args.prefer_sites)
        add_arg(discover_cmd, "--active-site-file", args.active_site_file)
        add_arg(discover_cmd, "--cofactor-sites-file", args.cofactor_sites_file)
        add_arg(discover_cmd, "--disulfide-sites-file", args.disulfide_sites_file)
        add_arg(discover_cmd, "--interface-sites-file", args.interface_sites_file)
        add_arg(discover_cmd, "--conserved-sites-file", args.conserved_sites_file)
        add_arg(discover_cmd, "--blocklist-sites-file", args.blocklist_sites_file)
        add_arg(discover_cmd, "--prefer-sites-file", args.prefer_sites_file)
        if args.allow_missing_functional_constraints:
            discover_cmd.append("--allow-missing-functional-constraints")
        if args.allow_functional_sites:
            discover_cmd.append("--allow-functional-sites")
        if args.include_blocked:
            discover_cmd.append("--include-blocked")
        discover_record = run_step("discover_sites", discover_cmd, args.dry_run)
        steps.append(discover_record)
        if discover_record["status"] == "failed":
            raise RuntimeError("discover_sites failed")

        library_cmd = [
            sys.executable,
            str(library_script),
            "--sequence-fasta",
            str(Path(args.sequence_fasta).resolve()),
            "--site-file",
            out_paths["site_specs"],
            "--max-mutations",
            str(args.max_mutations),
            "--max-candidates",
            str(args.max_candidates),
            "--disallow",
            args.disallow.upper(),
            "--output-csv",
            out_paths["library_csv"],
            "--output-fasta",
            out_paths["library_fasta"],
            "--output-list",
            out_paths["library_list"],
            "--output-metadata",
            out_paths["library_metadata_json"],
        ]
        if args.include_wt_target:
            library_cmd.append("--include-wt-target")
        if args.allow_duplicate_sequences:
            library_cmd.append("--allow-duplicate-sequences")
        if protected_sites:
            library_cmd.extend(["--protected-sites", encode_positions(protected_sites)])
        elif args.allow_missing_protected:
            library_cmd.append("--allow-missing-protected")
        if args.allow_protected_sites:
            library_cmd.append("--allow-protected-sites")
        library_record = run_step("generate_library", library_cmd, args.dry_run)
        steps.append(library_record)
        if library_record["status"] == "failed":
            raise RuntimeError("generate_library failed")

        if args.structure:
            mapper_cmd = [
                sys.executable,
                str(mapper_script),
                "--sequence-fasta",
                str(Path(args.sequence_fasta).resolve()),
                "--structure",
                str(Path(args.structure).resolve()),
                "--output-json",
                out_paths["mapping_json"],
                "--output-tsv",
                out_paths["mapping_tsv"],
                "--min-identity",
                str(args.mapping_min_identity),
                "--min-coverage",
                str(args.mapping_min_coverage),
            ]
            add_arg(mapper_cmd, "--chain", args.chain)
            if args.mapping_strict:
                mapper_cmd.append("--strict")
            mapper_record = run_step("map_sequence_structure", mapper_cmd, args.dry_run)
            steps.append(mapper_record)
            if mapper_record["status"] == "failed":
                raise RuntimeError("map_sequence_structure failed")

        if args.run_foldx:
            foldx_cmd = [
                sys.executable,
                str(foldx_script),
                "--structure",
                str(Path(args.structure).resolve()),
                "--mutations-file",
                out_paths["library_list"],
                "--foldx-binary",
                args.foldx_binary,
                "--output-mutation-format",
                args.foldx_output_mutation_format,
                "--chain",
                args.foldx_chain,
                "--output-file",
                args.foldx_output_file,
                "--ddg-column",
                str(args.foldx_ddg_column),
                "--timeout-sec",
                str(args.foldx_timeout_sec),
                "--output-csv",
                out_paths["foldx_csv"],
                "--output-json",
                out_paths["foldx_json"],
            ]
            if args.structure:
                foldx_cmd.extend(["--mapping-json", out_paths["mapping_json"]])
            if args.foldx_dry_run:
                foldx_cmd.append("--dry-run")
            if args.foldx_allow_insertion_codes:
                foldx_cmd.append("--allow-insertion-codes")
            if args.foldx_no_validate_structure_aa:
                foldx_cmd.append("--no-validate-structure-aa")
            for extra in args.foldx_extra_arg:
                foldx_cmd.extend(["--extra-arg", extra])
            foldx_record = run_step("foldx_batch", foldx_cmd, args.dry_run)
            steps.append(foldx_record)
            if foldx_record["status"] == "failed":
                raise RuntimeError("foldx_batch failed")

        if args.run_consensus:
            consensus_cmd = [
                sys.executable,
                str(consensus_script),
                "--input",
                out_paths["foldx_csv"],
                "--metrics",
                args.consensus_metrics,
                "--normalization",
                args.consensus_normalization,
                "--min-metrics",
                str(args.consensus_min_metrics),
                "--output",
                out_paths["consensus_csv"],
                "--summary-json",
                out_paths["consensus_json"],
            ]
            add_arg(consensus_cmd, "--weights", args.consensus_weights)
            add_arg(consensus_cmd, "--higher-is-better", args.consensus_higher_is_better)
            if args.consensus_strict_numeric:
                consensus_cmd.append("--strict-numeric")
            consensus_record = run_step("consensus_rank", consensus_cmd, args.dry_run)
            steps.append(consensus_record)
            if consensus_record["status"] == "failed":
                raise RuntimeError("consensus_rank failed")
    except Exception as exc:  # noqa: BLE001
        failure = str(exc)
        print(f"Pipeline failed: {failure}", file=sys.stderr)

    finished_at = datetime.now(timezone.utc)
    manifest = {
        "started_at_utc": started_at.isoformat(),
        "finished_at_utc": finished_at.isoformat(),
        "duration_seconds": round((finished_at - started_at).total_seconds(), 3),
        "status": ("failed" if failure else ("dry_run" if args.dry_run else "ok")),
        "failure": failure,
        "inputs": {
            "sequence_fasta": str(Path(args.sequence_fasta).resolve()),
            "structure": (str(Path(args.structure).resolve()) if args.structure else ""),
            "objective": args.objective,
            "top_n": args.top_n,
            "max_targets_per_site": args.max_targets_per_site,
            "max_mutations": args.max_mutations,
            "max_candidates": args.max_candidates,
        },
        "constraints": {
            "functional_constraints": functional_constraints,
            "protected_sites": sorted(protected_sites),
            "protected_site_sources": derived_protected_sources,
            "allow_missing_functional_constraints": args.allow_missing_functional_constraints,
            "allow_missing_protected": args.allow_missing_protected,
            "allow_functional_sites": args.allow_functional_sites,
            "allow_protected_sites": args.allow_protected_sites,
        },
        "steps": steps,
        "outputs": out_paths,
    }
    manifest_path = Path(out_paths["manifest_json"])
    with manifest_path.open("w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"Manifest: {manifest_path}")
    if failure:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
