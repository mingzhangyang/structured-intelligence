#!/usr/bin/env python3
"""
Run lightweight, deterministic checks for skill eval cases.

The evaluator reads eval definitions (prompt + expectations) and response texts,
then maps each expectation to executable keyword/rule checks.

Supported response formats:
- JSON:  [{ "name": "...", "response": "..." }, ...]
- JSONL: one JSON object per line with at least {"name", "response"}

Usage examples:
  python scripts/run_skill_evals.py \
    --evals evals.json \
    --responses responses.json \
    --output-json eval_report.json

  python scripts/run_skill_evals.py \
    --evals evals.json \
    --responses responses.jsonl \
    --output-json eval_report.json \
    --output-markdown eval_report.md \
    --fail-under 0.75

  python scripts/run_skill_evals.py \
    --evals evals.json \
    --dump-template responses.template.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


TOOL_WORDS = {
    "foldx",
    "rosetta",
    "dynamut",
    "duet",
    "sdm",
    "alphafold",
    "colabfold",
    "esmfold",
    "ddg_monomer",
    "cartesian_ddg",
}


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower()).strip()


def contains_any(text: str, terms: list[str]) -> bool:
    return any(term in text for term in terms)


def count_tools(text: str) -> int:
    found = {tool for tool in TOOL_WORDS if tool in text}
    return len(found)


def extract_named_response(item: dict[str, object]) -> tuple[str, str]:
    if not isinstance(item, dict):
        raise ValueError("Each response item must be a JSON object.")
    name = str(item.get("name", "")).strip()
    if not name:
        raise ValueError("Each response item must include non-empty 'name'.")
    response = ""
    for key in ("response", "output", "answer"):
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            response = value
            break
    if not response:
        raise ValueError(f"Response item '{name}' must include 'response' (or output/answer).")
    return name, response


def load_json(path: str) -> object:
    with Path(path).open() as handle:
        return json.load(handle)


def load_jsonl(path: str) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    with Path(path).open() as handle:
        for idx, line in enumerate(handle, start=1):
            text = line.strip()
            if not text:
                continue
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSONL at line {idx}: {exc}") from exc
            if not isinstance(parsed, dict):
                raise ValueError(f"JSONL line {idx} must be an object.")
            items.append(parsed)
    return items


def load_responses(path: str) -> dict[str, str]:
    suffix = Path(path).suffix.lower()
    if suffix == ".jsonl":
        raw_items = load_jsonl(path)
    else:
        payload = load_json(path)
        if not isinstance(payload, list):
            raise ValueError("Responses JSON must be an array of objects.")
        raw_items = payload

    out: dict[str, str] = {}
    for raw in raw_items:
        name, response = extract_named_response(raw)
        out[name] = response
    return out


@dataclass
class CheckResult:
    passed: bool
    evidence: str


def check_two_methods(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    n_tools = count_tools(n)
    return CheckResult(
        passed=n_tools >= 2,
        evidence=f"mentioned_tools={n_tools}",
    )


def check_plddt_not_direct_metric(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_plddt = "plddt" in n
    negation = contains_any(
        n,
        [
            "not a direct stability metric",
            "not direct stability",
            "not a stability metric",
            "cannot infer stability from plddt",
            "do not rank by plddt alone",
            "not rank by plddt alone",
        ],
    )
    return CheckResult(
        passed=has_plddt and negation,
        evidence=f"has_plddt={has_plddt}; negation={negation}",
    )


def check_structure_source(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["pdb", "alphafold", "experimental structure", "structure source", "model"])
    return CheckResult(passed=ok, evidence=f"structure_source_terms={ok}")


def check_structural_context(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(
        n,
        [
            "active site",
            "h-bond",
            "hydrogen bond",
            "conservation",
            "surface",
            "loop",
            "core",
            "distance",
            "microenvironment",
        ],
    )
    return CheckResult(passed=ok, evidence=f"structural_context_terms={ok}")


def check_sign_convention(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_ddg = "ddg" in n or "delta delta g" in n or "ΔΔg" in response
    has_sign = contains_any(
        n,
        [
            "sign convention",
            "negative ddg",
            "under tool convention",
            "confirm sign",
            "directionality",
        ],
    )
    return CheckResult(passed=has_ddg and has_sign, evidence=f"has_ddg={has_ddg}; sign_terms={has_sign}")


def check_consensus_or_confidence(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_consensus = "consensus" in n
    has_conf = contains_any(n, ["confidence", "support fraction", "support count", "high confidence"])
    has_rank = contains_any(n, ["rank", "priorit", "top candidate"])
    ok = (has_consensus and (has_conf or has_rank)) or (has_rank and has_conf)
    return CheckResult(passed=ok, evidence=f"consensus={has_consensus}; confidence={has_conf}; rank={has_rank}")


def check_validation_recommendation(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["wet-lab", "experimental validation", "validate experimentally", "confirmatory experiment"])
    return CheckResult(passed=ok, evidence=f"validation_terms={ok}")


def check_mutation_space_constraints(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_constraints = contains_any(n, ["avoid catalytic", "constraint", "mutation scope", "cap combinatorial", "k <="])
    return CheckResult(passed=has_constraints, evidence=f"constraint_terms={has_constraints}")


def check_structure_aware_rationale(expectation: str, response: str) -> CheckResult:
    return check_structural_context(expectation, response)


def check_combinatorial_limit(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["combinatorial", "k <=", "limit combinations", "search explosion", "max-mutations"])
    return CheckResult(passed=ok, evidence=f"combinatorial_limit_terms={ok}")


def check_ranked_with_evidence(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_rank = contains_any(n, ["rank", "priorit", "top", "shortlist"])
    has_evidence = contains_any(n, ["support", "evidence", "across tools", "consensus"])
    return CheckResult(passed=has_rank and has_evidence, evidence=f"rank={has_rank}; evidence={has_evidence}")


def check_explicit_assumptions(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["assumption", "protonation", "chain", "ligand", "cofactor", "ph", "temperature"])
    return CheckResult(passed=ok, evidence=f"assumption_terms={ok}")


def check_sequence_track(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_seq_mode = contains_any(n, ["sequence-only", "no structure", "structure is missing", "ai-assisted", "alphafold"])
    return CheckResult(passed=has_seq_mode, evidence=f"sequence_track_terms={has_seq_mode}")


def check_ddg_or_learned(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_ddg = "ddg" in n
    has_learned = contains_any(n, ["learned predictor", "stability predictor", "model"])
    return CheckResult(passed=(has_ddg or has_learned), evidence=f"ddg={has_ddg}; learned={has_learned}")


def check_reproducible_batch(expectation: str, response: str) -> CheckResult:
    _ = expectation
    has_cmd = "python scripts/" in response or "```bash" in response
    n = normalize(response)
    has_repro = contains_any(n, ["reproducible", "batch", "workflow", "same settings"])
    return CheckResult(passed=has_cmd and has_repro, evidence=f"command_block={has_cmd}; reproducible_terms={has_repro}")


def check_mapping_first(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_mapping = contains_any(n, ["mapping", "map residues", "numbering mismatch", "seq_to_structure"])
    return CheckResult(passed=has_mapping, evidence=f"mapping_terms={has_mapping}")


def check_prevent_direct_scoring(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_guardrail = contains_any(
        n,
        [
            "before scoring",
            "do not score before mapping",
            "prevent direct scoring",
            "validate mapping first",
        ],
    )
    return CheckResult(passed=has_guardrail, evidence=f"guardrail_terms={has_guardrail}")


def check_chain_numbering_assumptions(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["chain", "numbering", "assumption"])
    return CheckResult(passed=ok, evidence=f"chain_numbering_assumption_terms={ok}")


def check_normalization(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["normalize", "normalization", "rank normalization", "minmax"])
    return CheckResult(passed=ok, evidence=f"normalization_terms={ok}")


def check_metric_direction(expectation: str, response: str) -> CheckResult:
    return check_sign_convention(expectation, response)


def check_support_count_fraction(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["support count", "support fraction", "across methods"])
    return CheckResult(passed=ok, evidence=f"support_terms={ok}")


def check_final_ranked_list(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["ranked", "rank", "prioritized", "top candidates", "shortlist"])
    return CheckResult(passed=ok, evidence=f"ranked_output_terms={ok}")


def check_all_19(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = "19" in n and contains_any(n, ["non-wt", "alternatives", "all substitutions", "saturation"])
    return CheckResult(passed=ok, evidence=f"all_19_terms={ok}")


def check_fast_first_pass(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["fast", "first-pass", "prefilter", "foldx", "esmfold"])
    return CheckResult(passed=ok, evidence=f"fast_first_pass_terms={ok}")


def check_shortlist_uncertainty(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_short = contains_any(n, ["shortlist", "top candidates", "prioritized list"])
    has_unc = contains_any(n, ["uncertain", "uncertainty", "confidence", "caveat"])
    return CheckResult(passed=has_short and has_unc, evidence=f"shortlist={has_short}; uncertainty={has_unc}")


def check_orthogonal_validation(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    ok = contains_any(n, ["orthogonal", "second method", "re-score", "experimental validation"])
    return CheckResult(passed=ok, evidence=f"orthogonal_terms={ok}")


def check_interface_predictor(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_interface_context = contains_any(n, ["interface", "assembly", "oligomer", "binding"])
    has_interface_tool = contains_any(
        n,
        [
            "mcsm-ppi",
            "mutabind",
            "beatmusic",
            "bindprofx",
            "flex ddg",
            "interface ddg",
            "complex ddg",
        ],
    )
    return CheckResult(
        passed=has_interface_context and has_interface_tool,
        evidence=f"interface_context={has_interface_context}; interface_tool={has_interface_tool}",
    )


def check_af3_caveat(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_af3 = contains_any(n, ["alphafold3", "af3"])
    has_caveat = contains_any(
        n,
        [
            "not always better",
            "context-dependent",
            "mixed global",
            "not guaranteed",
            "does not always outperform",
        ],
    )
    return CheckResult(passed=has_af3 and has_caveat, evidence=f"af3={has_af3}; caveat={has_caveat}")


def check_destabilizing_bias(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_bias = contains_any(
        n,
        [
            "destabilizing bias",
            "bias toward destabilizing",
            "low recall for stabilizing",
            "stabilizing false negatives",
        ],
    )
    has_guard = contains_any(n, ["tentative", "orthogonal", "re-score", "validate experimentally", "uncertainty"])
    return CheckResult(passed=has_bias and has_guard, evidence=f"bias={has_bias}; guard={has_guard}")


def check_calibration_panel(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_panel = contains_any(n, ["calibrate", "reference panel", "known mutations", "homologous scaffold"])
    has_classes = contains_any(n, ["stabilizing", "neutral", "destabilizing"])
    return CheckResult(passed=has_panel and has_classes, evidence=f"panel={has_panel}; classes={has_classes}")


def check_objective_specific_signal(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_objective = contains_any(n, ["objective-specific", "thermostability", "ph tolerance", "solvent tolerance"])
    has_signal = contains_any(n, ["delta-tm", "tm", "temperature-oriented", "assay context"])
    return CheckResult(
        passed=has_objective and has_signal,
        evidence=f"objective={has_objective}; signal={has_signal}",
    )


def check_site_discovery_before_library(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_discovery = contains_any(n, ["candidate site", "site discovery", "rank sites", "discover_candidate_sites"])
    has_order = contains_any(n, ["before library", "before enumeration", "before generating", "first step"])
    has_library = contains_any(n, ["library", "site-file", "generate_mutation_library"])
    return CheckResult(
        passed=has_discovery and has_order and has_library,
        evidence=f"discovery={has_discovery}; order={has_order}; library={has_library}",
    )


def check_structural_site_context(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_active_shell = contains_any(n, ["active-shell", "active shell", "distance to active site", "second shell"])
    has_exposure_or_flex = contains_any(
        n,
        [
            "exposure",
            "surface",
            "boundary",
            "contact count",
            "flexibility",
            "b-factor",
            "bfactor",
        ],
    )
    return CheckResult(
        passed=has_active_shell and has_exposure_or_flex,
        evidence=f"active_shell={has_active_shell}; exposure_or_flex={has_exposure_or_flex}",
    )


def check_functional_blocklist(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_block = contains_any(n, ["blocklist", "exclude", "avoid", "blocked"])
    has_functional = contains_any(n, ["catalytic", "cofactor", "metal", "disulfide"])
    return CheckResult(passed=has_block and has_functional, evidence=f"block={has_block}; functional={has_functional}")


def check_ranked_sites_with_specs(expectation: str, response: str) -> CheckResult:
    _ = expectation
    n = normalize(response)
    has_ranked = contains_any(n, ["ranked site", "ranked candidates", "priority", "top sites"])
    has_rationale = "rationale" in n
    has_spec = contains_any(n, ["site spec", "site-spec", "--site-file", "a123:"])
    has_pattern = re.search(r"[A-Z]\d+:[A-Z]+", response) is not None
    return CheckResult(
        passed=has_ranked and has_rationale and (has_spec or has_pattern),
        evidence=f"ranked={has_ranked}; rationale={has_rationale}; spec_term={has_spec}; spec_pattern={has_pattern}",
    )


def check_generic_overlap(expectation: str, response: str) -> CheckResult:
    stop = {
        "a",
        "an",
        "the",
        "and",
        "or",
        "to",
        "of",
        "for",
        "with",
        "by",
        "from",
        "on",
        "in",
        "is",
        "are",
        "be",
        "as",
        "that",
        "this",
        "at",
        "before",
        "after",
        "across",
        "using",
        "uses",
        "use",
    }
    e_tokens = [
        tok
        for tok in re.findall(r"[a-z0-9_+-]+", normalize(expectation))
        if len(tok) >= 4 and tok not in stop
    ]
    if not e_tokens:
        return CheckResult(passed=True, evidence="empty_expectation_tokens")
    n = normalize(response)
    hits = sum(1 for tok in e_tokens if tok in n)
    ratio = hits / len(e_tokens)
    return CheckResult(passed=ratio >= 0.35, evidence=f"token_overlap={hits}/{len(e_tokens)}")


RuleFn = Callable[[str, str], CheckResult]


@dataclass
class ExpectationRule:
    name: str
    triggers: tuple[str, ...]
    fn: RuleFn


RULES: list[ExpectationRule] = [
    ExpectationRule("two_methods", ("at least two", "two complementary"), check_two_methods),
    ExpectationRule("plddt_not_metric", ("plddt is not", "not a direct stability metric"), check_plddt_not_direct_metric),
    ExpectationRule("structure_source", ("structure source", "retrieves or validates"), check_structure_source),
    ExpectationRule("structural_context", ("structural context", "target residue"), check_structural_context),
    ExpectationRule("sign_convention", ("sign convention", "directionality"), check_sign_convention),
    ExpectationRule("consensus_confidence", ("consensus-style", "confidence statement"), check_consensus_or_confidence),
    ExpectationRule("wetlab_validation", ("wet-lab validation", "validation"), check_validation_recommendation),
    ExpectationRule("mutation_constraints", ("mutation-space constraints",), check_mutation_space_constraints),
    ExpectationRule("structure_rationale", ("structure-aware rationale",), check_structure_aware_rationale),
    ExpectationRule("combinatorial_limit", ("combinatorial limits", "search explosion"), check_combinatorial_limit),
    ExpectationRule("ranked_evidence", ("ranked candidates", "evidence provenance"), check_ranked_with_evidence),
    ExpectationRule("explicit_assumptions", ("explicit assumptions", "assumptions"), check_explicit_assumptions),
    ExpectationRule("sequence_track", ("sequence/ai-assisted track", "structure is missing"), check_sequence_track),
    ExpectationRule("ddg_or_learned", ("downstream ddg", "learned predictors"), check_ddg_or_learned),
    ExpectationRule("repro_batch", ("reproducible batch-oriented workflow",), check_reproducible_batch),
    ExpectationRule("mapping_risk", ("numbering mismatch risk", "explicit mapping"), check_mapping_first),
    ExpectationRule("mapping_before_scoring", ("before structure-based scoring", "mis-mapped positions"), check_prevent_direct_scoring),
    ExpectationRule("chain_numbering_assumptions", ("chain/numbering assumptions",), check_chain_numbering_assumptions),
    ExpectationRule("normalization", ("explicit normalization",), check_normalization),
    ExpectationRule("metric_direction", ("mixed metric directions", "directionality"), check_metric_direction),
    ExpectationRule("support_fraction", ("support count", "support fraction"), check_support_count_fraction),
    ExpectationRule("final_ranked", ("final ranked candidate list", "ranked candidate"), check_final_ranked_list),
    ExpectationRule("all_19", ("all 19", "19 non-wt"), check_all_19),
    ExpectationRule("fast_first_pass", ("fast first-pass",), check_fast_first_pass),
    ExpectationRule("shortlist_uncertainty", ("shortlist", "uncertainty"), check_shortlist_uncertainty),
    ExpectationRule("orthogonal_validation", ("orthogonal", "validation"), check_orthogonal_validation),
    ExpectationRule("interface_predictor", ("interface-focused predictor", "interface-aware scoring"), check_interface_predictor),
    ExpectationRule("af3_caveat", ("af3 caveat", "alphafold3 caveat"), check_af3_caveat),
    ExpectationRule("destabilizing_bias", ("destabilizing-class bias", "stabilizing predictions as tentative"), check_destabilizing_bias),
    ExpectationRule("calibration_panel", ("calibration panel", "known stabilizing/neutral/destabilizing"), check_calibration_panel),
    ExpectationRule("objective_specific_signal", ("objective-specific tool choice", "temperature-oriented signal"), check_objective_specific_signal),
    ExpectationRule(
        "site_discovery_before_library",
        ("candidate-site discovery before mutation-library enumeration",),
        check_site_discovery_before_library,
    ),
    ExpectationRule(
        "structural_site_context",
        ("active-shell distance and exposure or flexibility",),
        check_structural_site_context,
    ),
    ExpectationRule(
        "functional_blocklist",
        ("blocklist guardrails for catalytic or cofactor or disulfide positions",),
        check_functional_blocklist,
    ),
    ExpectationRule(
        "ranked_sites_with_specs",
        ("ranked site candidates with rationale and site specs for downstream generation",),
        check_ranked_sites_with_specs,
    ),
]


def choose_rule(expectation: str) -> ExpectationRule | None:
    n = normalize(expectation)
    for rule in RULES:
        if any(trigger in n for trigger in rule.triggers):
            return rule
    return None


def load_evals(path: str) -> list[dict[str, object]]:
    payload = load_json(path)
    if not isinstance(payload, list):
        raise ValueError("Evals file must be a JSON array.")
    out: list[dict[str, object]] = []
    for idx, item in enumerate(payload, start=1):
        if not isinstance(item, dict):
            raise ValueError(f"Evals item #{idx} must be an object.")
        name = str(item.get("name", "")).strip()
        prompt = str(item.get("prompt", "")).strip()
        expectations = item.get("expectations")
        if not name or not prompt:
            raise ValueError(f"Evals item #{idx} requires non-empty name and prompt.")
        if not isinstance(expectations, list) or not expectations:
            raise ValueError(f"Evals item '{name}' must include non-empty expectations list.")
        clean_expectations = [str(x).strip() for x in expectations if str(x).strip()]
        if not clean_expectations:
            raise ValueError(f"Evals item '{name}' has no usable expectations.")
        out.append(
            {
                "name": name,
                "prompt": prompt,
                "expectations": clean_expectations,
            }
        )
    return out


def write_markdown(path: str, report: dict[str, object]) -> None:
    lines: list[str] = []
    lines.append("# Skill Eval Report")
    lines.append("")
    lines.append(f"- Cases: {report['summary']['total_cases']}")
    lines.append(f"- Case pass rate: {report['summary']['case_pass_rate']:.3f}")
    lines.append(f"- Expectation pass rate: {report['summary']['expectation_pass_rate']:.3f}")
    lines.append("")
    for case in report["cases"]:
        lines.append(f"## {case['name']}")
        lines.append("")
        lines.append(f"- passed: {case['passed']}")
        lines.append(f"- score: {case['score']:.3f}")
        lines.append("")
        for item in case["checks"]:
            mark = "PASS" if item["passed"] else "FAIL"
            lines.append(f"- [{mark}] {item['expectation']}")
            lines.append(f"  - rule: {item['rule']}")
            lines.append(f"  - evidence: {item['evidence']}")
        lines.append("")
    Path(path).write_text("\n".join(lines))


def dump_template(path: str, evals: list[dict[str, object]]) -> None:
    template = []
    for case in evals:
        template.append(
            {
                "name": case["name"],
                "prompt": case["prompt"],
                "response": "",
            }
        )
    with Path(path).open("w") as handle:
        json.dump(template, handle, indent=2)
        handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run deterministic checks for skill eval responses.")
    parser.add_argument("--evals", required=True, help="Path to evals.json")
    parser.add_argument("--responses", help="Path to responses (.json or .jsonl)")
    parser.add_argument("--output-json", help="Write machine-readable report JSON")
    parser.add_argument("--output-markdown", help="Optional markdown summary output")
    parser.add_argument(
        "--fail-under",
        type=float,
        default=0.0,
        help="Fail (exit 1) if expectation pass rate is below this threshold [0..1].",
    )
    parser.add_argument(
        "--require-all-cases",
        action="store_true",
        help="Fail (exit 1) if any case has a failing expectation.",
    )
    parser.add_argument(
        "--dump-template",
        help="Write response template JSON and exit (does not evaluate).",
    )
    args = parser.parse_args()

    if args.fail_under < 0 or args.fail_under > 1:
        raise ValueError("--fail-under must be in [0, 1].")

    evals = load_evals(args.evals)

    if args.dump_template:
        dump_template(args.dump_template, evals)
        print(f"Wrote template: {args.dump_template}")
        return

    if not args.responses:
        raise ValueError("--responses is required unless --dump-template is used.")

    responses = load_responses(args.responses)

    case_reports: list[dict[str, object]] = []
    total_expectations = 0
    passed_expectations = 0
    passed_cases = 0
    missing_responses: list[str] = []

    for case in evals:
        name = str(case["name"])
        prompt = str(case["prompt"])
        expectations = list(case["expectations"])
        response = responses.get(name, "")
        if not response:
            missing_responses.append(name)

        checks: list[dict[str, object]] = []
        case_passed = True
        case_pass_count = 0
        for expectation in expectations:
            total_expectations += 1
            if not response:
                passed = False
                evidence = "missing_response"
                rule_name = "none"
            else:
                rule = choose_rule(expectation)
                if rule is None:
                    result = check_generic_overlap(expectation, response)
                    rule_name = "generic_overlap"
                else:
                    result = rule.fn(expectation, response)
                    rule_name = rule.name
                passed = result.passed
                evidence = result.evidence
            if passed:
                passed_expectations += 1
                case_pass_count += 1
            else:
                case_passed = False
            checks.append(
                {
                    "expectation": expectation,
                    "passed": passed,
                    "rule": rule_name,
                    "evidence": evidence,
                }
            )

        score = case_pass_count / len(expectations)
        if case_passed:
            passed_cases += 1
        case_reports.append(
            {
                "name": name,
                "prompt": prompt,
                "passed": case_passed,
                "score": score,
                "checks": checks,
            }
        )

    case_pass_rate = (passed_cases / len(evals)) if evals else 0.0
    expectation_pass_rate = (passed_expectations / total_expectations) if total_expectations else 0.0

    report = {
        "summary": {
            "total_cases": len(evals),
            "total_expectations": total_expectations,
            "passed_cases": passed_cases,
            "passed_expectations": passed_expectations,
            "case_pass_rate": case_pass_rate,
            "expectation_pass_rate": expectation_pass_rate,
            "missing_responses": missing_responses,
        },
        "cases": case_reports,
    }

    print(
        f"cases_passed={passed_cases}/{len(evals)} "
        f"expectations_passed={passed_expectations}/{total_expectations} "
        f"expectation_pass_rate={expectation_pass_rate:.3f}"
    )
    if missing_responses:
        print("missing_responses=" + ",".join(missing_responses))

    for case in case_reports:
        status = "PASS" if case["passed"] else "FAIL"
        print(f"[{status}] {case['name']} score={case['score']:.3f}")

    if args.output_json:
        with Path(args.output_json).open("w") as handle:
            json.dump(report, handle, indent=2)
            handle.write("\n")
        print(f"wrote_report_json={args.output_json}")

    if args.output_markdown:
        write_markdown(args.output_markdown, report)
        print(f"wrote_report_markdown={args.output_markdown}")

    should_fail = False
    if expectation_pass_rate < args.fail_under:
        should_fail = True
    if args.require_all_cases and passed_cases < len(evals):
        should_fail = True
    if should_fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
