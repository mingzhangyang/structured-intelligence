#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from urllib import error, parse, request


DEFAULT_BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
DEFAULT_TOOL = "structured-intelligence-ncbi-eutilities-assistant"
REQUEST_METHOD_CHOICES = ("auto", "get", "post")


def fail(message: str) -> int:
    print(f"Error: {message}", file=sys.stderr)
    return 1


def add_common_request_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--email",
        default=os.environ.get("NCBI_EMAIL"),
        help="Contact email for the caller. Defaults to $NCBI_EMAIL when set.",
    )
    parser.add_argument(
        "--tool",
        default=os.environ.get("NCBI_TOOL", DEFAULT_TOOL),
        help=f"Tool name sent to NCBI. Defaults to $NCBI_TOOL or {DEFAULT_TOOL}.",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("NCBI_API_KEY"),
        help="NCBI API key. Defaults to $NCBI_API_KEY when set.",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("NCBI_EUTILS_BASE_URL", DEFAULT_BASE_URL),
        help=f"Override the E-utilities base URL. Default: {DEFAULT_BASE_URL}",
    )
    parser.add_argument(
        "--out",
        help="Optional output file path. If omitted, response is written to stdout.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned request instead of sending it.",
    )
    parser.add_argument(
        "--request-method",
        choices=REQUEST_METHOD_CHOICES,
        default="auto",
        help="Force GET or POST, or let the script choose automatically.",
    )


def add_id_source_args(parser: argparse.ArgumentParser) -> None:
    ids_group = parser.add_mutually_exclusive_group()
    ids_group.add_argument("--id", help="Comma-separated UID list.")
    ids_group.add_argument(
        "--id-file",
        type=Path,
        help="File containing IDs separated by commas, tabs, spaces, or newlines.",
    )
    parser.add_argument("--webenv", help="Entrez History WebEnv token.")
    parser.add_argument("--query-key", help="Entrez History query_key.")


def load_id_file(path: Path) -> str:
    if not path.is_file():
        raise ValueError(f"ID file not found: {path}")
    raw = path.read_text(encoding="utf-8")
    tokens = [token for token in re.split(r"[\s,]+", raw.strip()) if token]
    if not tokens:
        raise ValueError(f"ID file is empty: {path}")
    return ",".join(tokens)


def normalize_ids(value: str) -> str:
    tokens = [token for token in re.split(r"[\s,]+", value.strip()) if token]
    if not tokens:
        raise ValueError("ID list is empty")
    return ",".join(tokens)


def resolve_id_source(args: argparse.Namespace, require: bool = True) -> tuple[str | None, bool]:
    ids: str | None = None
    if getattr(args, "id_file", None):
        ids = load_id_file(args.id_file)
    elif getattr(args, "id", None):
        ids = normalize_ids(args.id)

    has_webenv = bool(getattr(args, "webenv", None))
    has_query_key = bool(getattr(args, "query_key", None))
    has_history = has_webenv or has_query_key

    if has_history and not (has_webenv and has_query_key):
        raise ValueError("Both --webenv and --query-key are required for history-based retrieval")
    if ids and has_history:
        raise ValueError("Provide either IDs or history parameters, not both")
    if require and not ids and not has_history:
        raise ValueError("Provide --id / --id-file or both --webenv and --query-key")
    return ids, has_history


def build_common_params(args: argparse.Namespace) -> dict[str, str]:
    params: dict[str, str] = {}
    if getattr(args, "tool", None):
        params["tool"] = args.tool
    if getattr(args, "email", None):
        params["email"] = args.email
    if getattr(args, "api_key", None):
        params["api_key"] = args.api_key
    return params


def add_optional_param(params: dict[str, str], name: str, value: Any) -> None:
    if value is None:
        return
    if isinstance(value, str) and value == "":
        return
    params[name] = str(value)


def redact_params(params: dict[str, str]) -> dict[str, str]:
    redacted = dict(params)
    if "api_key" in redacted:
        redacted["api_key"] = "***REDACTED***"
    return redacted


def choose_method(endpoint: str, args: argparse.Namespace, params: dict[str, str]) -> str:
    if args.request_method != "auto":
        return args.request_method.upper()
    if endpoint == "epost":
        return "POST"
    if getattr(args, "id_file", None):
        return "POST"
    ids = params.get("id", "")
    if ids:
        if len(ids.split(",")) > 200:
            return "POST"
        if len(ids) > 1200:
            return "POST"
    encoded = parse.urlencode(params)
    if len(encoded) > 1500:
        return "POST"
    return "GET"


def endpoint_url(base_url: str, endpoint: str) -> str:
    return f"{base_url.rstrip('/')}/{endpoint}.fcgi"


def build_request_plan(
    endpoint: str,
    params: dict[str, str],
    args: argparse.Namespace,
    *,
    redact: bool,
) -> dict[str, str | None]:
    method = choose_method(endpoint, args, params)
    base = endpoint_url(args.base_url, endpoint)
    plan_params = redact_params(params) if redact else params

    if method == "GET":
        url = f"{base}?{parse.urlencode(plan_params)}" if plan_params else base
        body = None
    else:
        url = base
        body = parse.urlencode(plan_params)

    return {
        "endpoint": endpoint,
        "method": method,
        "url": url,
        "body": body,
    }


def request_bytes(endpoint: str, params: dict[str, str], args: argparse.Namespace) -> bytes:
    plan = build_request_plan(endpoint, params, args, redact=False)
    body = plan["body"].encode("utf-8") if plan["body"] else None
    headers = {
        "User-Agent": args.tool or DEFAULT_TOOL,
        "Accept": "*/*",
    }
    req = request.Request(plan["url"], data=body, headers=headers, method=plan["method"])
    try:
        with request.urlopen(req) as response:
            return response.read()
    except error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise ValueError(f"HTTP {exc.code} for {endpoint}: {details.strip() or exc.reason}") from exc
    except error.URLError as exc:
        raise ValueError(f"Network error for {endpoint}: {exc.reason}") from exc


def write_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def write_json(path: Path, payload: Any) -> None:
    write_bytes(path, json.dumps(payload, indent=2, ensure_ascii=True).encode("utf-8"))


def decode_json_bytes(payload: bytes, label: str) -> dict[str, Any]:
    try:
        data = json.loads(payload.decode("utf-8"))
    except Exception as exc:
        raise ValueError(f"{label} did not return valid JSON") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{label} returned unexpected JSON root type")
    return data


def execute_request(endpoint: str, params: dict[str, str], args: argparse.Namespace) -> int:
    if args.dry_run:
        print(json.dumps(build_request_plan(endpoint, params, args, redact=True), indent=2, ensure_ascii=True))
        return 0

    try:
        payload = request_bytes(endpoint, params, args)
    except ValueError as exc:
        return fail(str(exc))

    if args.out:
        out_path = Path(args.out)
        write_bytes(out_path, payload)
    else:
        sys.stdout.buffer.write(payload)
    return 0


def default_fetch_extension(retmode: str, rettype: str | None) -> str:
    if retmode == "xml":
        return "xml"
    if retmode == "json":
        return "json"
    if rettype:
        cleaned = re.sub(r"[^a-z0-9]+", "-", rettype.lower()).strip("-")
        if cleaned:
            return cleaned
    cleaned_mode = re.sub(r"[^a-z0-9]+", "-", retmode.lower()).strip("-")
    return cleaned_mode or "txt"


def text_or_none(node: ET.Element | None) -> str | None:
    if node is None:
        return None
    text = "".join(node.itertext()).strip()
    return text or None


def collect_texts(node: ET.Element | None, path: str) -> list[str]:
    if node is None:
        return []
    values: list[str] = []
    for child in node.findall(path):
        text = text_or_none(child)
        if text:
            values.append(text)
    return values


def parse_pubmed_xml_records(payload: bytes) -> list[dict[str, Any]]:
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as exc:
        raise ValueError("PubMed EFetch did not return valid XML") from exc

    records: list[dict[str, Any]] = []
    for article in root.findall(".//PubmedArticle"):
        medline = article.find("MedlineCitation")
        article_meta = medline.find("Article") if medline is not None else None
        journal = article_meta.find("Journal") if article_meta is not None else None
        pub_date = journal.find("./JournalIssue/PubDate") if journal is not None else None

        pmid = text_or_none(medline.find("PMID") if medline is not None else None)
        title = text_or_none(article_meta.find("ArticleTitle") if article_meta is not None else None)

        abstract_sections: list[dict[str, str]] = []
        abstract_joined: list[str] = []
        if article_meta is not None:
            abstract = article_meta.find("Abstract")
            if abstract is not None:
                for abstract_text in abstract.findall("AbstractText"):
                    text = text_or_none(abstract_text)
                    if not text:
                        continue
                    label = abstract_text.get("Label")
                    category = abstract_text.get("NlmCategory")
                    item: dict[str, str] = {"text": text}
                    if label:
                        item["label"] = label
                    if category:
                        item["category"] = category
                    abstract_sections.append(item)
                    abstract_joined.append(f"{label}: {text}" if label else text)

        authors: list[dict[str, str]] = []
        if article_meta is not None:
            author_list = article_meta.find("AuthorList")
            if author_list is not None:
                for author in author_list.findall("Author"):
                    entry: dict[str, str] = {}
                    last_name = text_or_none(author.find("LastName"))
                    fore_name = text_or_none(author.find("ForeName"))
                    initials = text_or_none(author.find("Initials"))
                    collective = text_or_none(author.find("CollectiveName"))
                    if collective:
                        entry["collective_name"] = collective
                    if last_name:
                        entry["last_name"] = last_name
                    if fore_name:
                        entry["fore_name"] = fore_name
                    if initials:
                        entry["initials"] = initials
                    if entry:
                        authors.append(entry)

        publication_types = collect_texts(article_meta, "PublicationTypeList/PublicationType") if article_meta is not None else []
        keywords = collect_texts(medline, "KeywordList/Keyword") if medline is not None else []
        mesh_terms: list[str] = []
        if medline is not None:
            mesh_heading_list = medline.find("MeshHeadingList")
            if mesh_heading_list is not None:
                for heading in mesh_heading_list.findall("MeshHeading"):
                    descriptor = text_or_none(heading.find("DescriptorName"))
                    qualifiers = collect_texts(heading, "QualifierName")
                    if descriptor and qualifiers:
                        mesh_terms.append(f"{descriptor} | {'; '.join(qualifiers)}")
                    elif descriptor:
                        mesh_terms.append(descriptor)

        article_ids: dict[str, str] = {}
        pubmed_data = article.find("PubmedData")
        if pubmed_data is not None:
            article_id_list = pubmed_data.find("ArticleIdList")
            if article_id_list is not None:
                for article_id in article_id_list.findall("ArticleId"):
                    id_type = article_id.get("IdType")
                    value = text_or_none(article_id)
                    if id_type and value:
                        article_ids[id_type] = value

        pub_year = None
        if pub_date is not None:
            pub_year = text_or_none(pub_date.find("Year")) or text_or_none(pub_date.find("MedlineDate"))

        records.append(
            {
                "pmid": pmid,
                "title": title,
                "abstract": "\n\n".join(abstract_joined) if abstract_joined else None,
                "abstract_sections": abstract_sections,
                "journal": text_or_none(journal.find("Title") if journal is not None else None),
                "journal_iso": text_or_none(journal.find("ISOAbbreviation") if journal is not None else None),
                "publication_year": pub_year,
                "authors": authors,
                "publication_types": publication_types,
                "mesh_terms": mesh_terms,
                "keywords": keywords,
                "article_ids": article_ids,
            }
        )
    return records


def build_pubmed_workflow_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("pubmed-workflow", parents=parents, help="Run a higher-level PubMed retrieval workflow")
    parser.add_argument("--term", required=True, help="PubMed query term.")
    parser.add_argument("--retmax", type=int, default=20, help="Number of records to process in this batch.")
    parser.add_argument("--retstart", type=int, default=0, help="Starting offset for PubMed search results.")
    parser.add_argument("--sort", help="PubMed sort order.")
    parser.add_argument("--field", help="Optional field restriction for the search term.")
    parser.add_argument("--datetype", help="Date type filter.")
    parser.add_argument("--reldate", type=int, help="Relative date filter in days.")
    parser.add_argument("--mindate", help="Minimum date.")
    parser.add_argument("--maxdate", help="Maximum date.")
    parser.add_argument("--summary-version", help="ESummary version, such as 2.0.")
    parser.add_argument("--include-fetch", choices=("yes", "no"), default="yes")
    parser.add_argument("--fetch-retmode", default="xml", help="EFetch retmode for PubMed full retrieval.")
    parser.add_argument("--fetch-rettype", default="abstract", help="EFetch rettype for PubMed full retrieval.")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("pubmed-workflow-output"),
        help="Directory for esearch/esummary/efetch outputs and manifest.",
    )
    parser.add_argument("--manifest-out", type=Path, help="Optional explicit manifest path.")
    parser.set_defaults(handler=handle_pubmed_workflow)


def build_pubmed_review_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("pubmed-review", parents=parents, help="Run a PubMed literature-review and abstract-extraction workflow")
    parser.add_argument("--term", required=True, help="PubMed query term.")
    parser.add_argument("--retmax", type=int, default=20, help="Number of PubMed records to retrieve.")
    parser.add_argument("--retstart", type=int, default=0, help="Starting PubMed search offset.")
    parser.add_argument("--sort", help="PubMed sort order.")
    parser.add_argument("--field", help="Optional field restriction for the search term.")
    parser.add_argument("--datetype", help="Date type filter.")
    parser.add_argument("--reldate", type=int, help="Relative date filter in days.")
    parser.add_argument("--mindate", help="Minimum date.")
    parser.add_argument("--maxdate", help="Maximum date.")
    parser.add_argument("--summary-version", help="ESummary version, such as 2.0.")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("pubmed-review-output"),
        help="Directory for raw PubMed responses and extracted structured outputs.",
    )
    parser.add_argument("--manifest-out", type=Path, help="Optional explicit manifest path.")
    parser.add_argument("--records-out", type=Path, help="Optional explicit JSON output path for extracted records.")
    parser.add_argument("--records-jsonl-out", type=Path, help="Optional explicit JSONL output path for extracted records.")
    parser.set_defaults(handler=handle_pubmed_review)


def build_info_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("info", parents=parents, help="Call EInfo")
    parser.add_argument("--db", help="Entrez database name. Omit to list databases.")
    parser.add_argument("--version", help="EInfo version, such as 2.0.")
    parser.add_argument("--retmode", choices=("xml", "json"), default="json")
    parser.set_defaults(handler=handle_info)


def build_search_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("search", parents=parents, help="Call ESearch")
    parser.add_argument("--db", required=True, help="Entrez database name.")
    parser.add_argument("--term", required=True, help="Entrez search term.")
    parser.add_argument("--retmax", type=int, default=20)
    parser.add_argument("--retstart", type=int, default=0)
    parser.add_argument("--sort", help="Sort order.")
    parser.add_argument("--field", help="Field restriction.")
    parser.add_argument("--idtype", help="Identifier type where supported.")
    parser.add_argument("--datetype", help="Date type filter.")
    parser.add_argument("--reldate", type=int, help="Relative date range in days.")
    parser.add_argument("--mindate", help="Minimum date.")
    parser.add_argument("--maxdate", help="Maximum date.")
    parser.add_argument("--usehistory", choices=("y", "n"), default="n")
    parser.add_argument("--retmode", choices=("xml", "json"), default="json")
    parser.set_defaults(handler=handle_search)


def build_summary_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("summary", parents=parents, help="Call ESummary")
    parser.add_argument("--db", required=True, help="Entrez database name.")
    add_id_source_args(parser)
    parser.add_argument("--retstart", type=int)
    parser.add_argument("--retmax", type=int)
    parser.add_argument("--version", help="ESummary version, such as 2.0.")
    parser.add_argument("--retmode", choices=("xml", "json"), default="json")
    parser.set_defaults(handler=handle_summary)


def build_fetch_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("fetch", parents=parents, help="Call EFetch")
    parser.add_argument("--db", required=True, help="Entrez database name.")
    add_id_source_args(parser)
    parser.add_argument("--retstart", type=int)
    parser.add_argument("--retmax", type=int, help="Maximum records to return.")
    parser.add_argument("--retmode", help="Return mode, such as xml, text, or native.")
    parser.add_argument("--rettype", help="Return type, database-specific.")
    parser.add_argument("--seq-start", type=int, help="Sequence start coordinate where supported.")
    parser.add_argument("--seq-stop", type=int, help="Sequence stop coordinate where supported.")
    parser.add_argument("--strand", choices=("1", "2"), help="Sequence strand where supported.")
    parser.add_argument("--complexity", help="Sequence complexity level where supported.")
    parser.set_defaults(handler=handle_fetch)


def build_link_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("link", parents=parents, help="Call ELink")
    parser.add_argument("--dbfrom", required=True, help="Source Entrez database.")
    parser.add_argument("--db", help="Destination Entrez database.")
    add_id_source_args(parser)
    parser.add_argument("--cmd", help="ELink cmd value.")
    parser.add_argument("--linkname", help="Specific link name.")
    parser.add_argument("--term", help="Neighbor term filter.")
    parser.add_argument("--holding", help="Holding filter.")
    parser.add_argument("--retmode", choices=("xml", "json"), help="Return mode when supported.")
    parser.set_defaults(handler=handle_link)


def build_post_parser(subparsers: argparse._SubParsersAction[argparse.ArgumentParser], parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("post", parents=parents, help="Call EPost")
    parser.add_argument("--db", required=True, help="Entrez database name.")
    ids_group = parser.add_mutually_exclusive_group()
    ids_group.add_argument("--id", help="Comma-separated UID list.")
    ids_group.add_argument("--id-file", type=Path, help="File containing IDs to upload.")
    parser.add_argument("--webenv", help="Optional existing WebEnv for appending.")
    parser.set_defaults(handler=handle_post)


def handle_pubmed_workflow(args: argparse.Namespace) -> int:
    if args.out:
        return fail("pubmed-workflow writes multiple files; use --out-dir or --manifest-out instead of --out")

    out_dir: Path = args.out_dir
    manifest_path = args.manifest_out or out_dir / "manifest.json"
    search_path = out_dir / "esearch.json"
    summary_path = out_dir / "esummary.json"
    fetch_path = out_dir / f"efetch.{default_fetch_extension(args.fetch_retmode, args.fetch_rettype)}"

    search_params = build_common_params(args)
    search_params["db"] = "pubmed"
    search_params["term"] = args.term
    search_params["retmax"] = str(args.retmax)
    search_params["retstart"] = str(args.retstart)
    search_params["usehistory"] = "y"
    search_params["retmode"] = "json"
    add_optional_param(search_params, "sort", args.sort)
    add_optional_param(search_params, "field", args.field)
    add_optional_param(search_params, "datetype", args.datetype)
    add_optional_param(search_params, "reldate", args.reldate)
    add_optional_param(search_params, "mindate", args.mindate)
    add_optional_param(search_params, "maxdate", args.maxdate)

    summary_template = build_common_params(args)
    summary_template["db"] = "pubmed"
    summary_template["retmode"] = "json"
    add_optional_param(summary_template, "retstart", args.retstart)
    add_optional_param(summary_template, "retmax", args.retmax)
    add_optional_param(summary_template, "version", args.summary_version)
    summary_template["WebEnv"] = "<from esearch>"
    summary_template["query_key"] = "<from esearch>"

    fetch_template = build_common_params(args)
    fetch_template["db"] = "pubmed"
    fetch_template["WebEnv"] = "<from esearch>"
    fetch_template["query_key"] = "<from esearch>"
    add_optional_param(fetch_template, "retstart", args.retstart)
    add_optional_param(fetch_template, "retmax", args.retmax)
    add_optional_param(fetch_template, "retmode", args.fetch_retmode)
    add_optional_param(fetch_template, "rettype", args.fetch_rettype)

    if args.dry_run:
        plan: dict[str, Any] = {
            "workflow": "pubmed-workflow",
            "outputs": {
                "search": str(search_path),
                "summary": str(summary_path),
                "manifest": str(manifest_path),
            },
            "steps": [
                build_request_plan("esearch", search_params, args, redact=True),
                build_request_plan("esummary", summary_template, args, redact=True),
            ],
        }
        if args.include_fetch == "yes":
            plan["outputs"]["fetch"] = str(fetch_path)
            plan["steps"].append(build_request_plan("efetch", fetch_template, args, redact=True))
        print(json.dumps(plan, indent=2, ensure_ascii=True))
        return 0

    try:
        search_payload = request_bytes("esearch", search_params, args)
        search_json = decode_json_bytes(search_payload, "esearch")
        write_bytes(search_path, search_payload)

        search_result = search_json.get("esearchresult")
        if not isinstance(search_result, dict):
            raise ValueError("esearch response is missing 'esearchresult'")

        ids = search_result.get("idlist")
        if not isinstance(ids, list):
            ids = []
        ids = [str(value) for value in ids]

        count_raw = search_result.get("count", "0")
        try:
            total_count = int(str(count_raw))
        except ValueError:
            raise ValueError(f"Unexpected PubMed count value: {count_raw!r}") from None

        webenv = search_result.get("webenv")
        query_key = search_result.get("querykey")
        if total_count > 0 and (not webenv or not query_key):
            raise ValueError("PubMed workflow expected WebEnv and query_key from esearch but did not receive them")

        summary_path_written: str | None = None
        fetch_path_written: str | None = None

        if total_count > 0:
            summary_params = build_common_params(args)
            summary_params["db"] = "pubmed"
            summary_params["retmode"] = "json"
            summary_params["WebEnv"] = str(webenv)
            summary_params["query_key"] = str(query_key)
            add_optional_param(summary_params, "retstart", args.retstart)
            add_optional_param(summary_params, "retmax", args.retmax)
            add_optional_param(summary_params, "version", args.summary_version)
            summary_payload = request_bytes("esummary", summary_params, args)
            write_bytes(summary_path, summary_payload)
            summary_path_written = str(summary_path)

            if args.include_fetch == "yes":
                fetch_params = build_common_params(args)
                fetch_params["db"] = "pubmed"
                fetch_params["WebEnv"] = str(webenv)
                fetch_params["query_key"] = str(query_key)
                add_optional_param(fetch_params, "retstart", args.retstart)
                add_optional_param(fetch_params, "retmax", args.retmax)
                add_optional_param(fetch_params, "retmode", args.fetch_retmode)
                add_optional_param(fetch_params, "rettype", args.fetch_rettype)
                fetch_payload = request_bytes("efetch", fetch_params, args)
                write_bytes(fetch_path, fetch_payload)
                fetch_path_written = str(fetch_path)

        manifest = {
            "workflow": "pubmed-workflow",
            "term": args.term,
            "total_count": total_count,
            "retstart": args.retstart,
            "retmax": args.retmax,
            "returned_ids": ids,
            "webenv": webenv,
            "query_key": query_key,
            "paths": {
                "search": str(search_path),
                "summary": summary_path_written,
                "fetch": fetch_path_written,
            },
            "fetch": {
                "enabled": args.include_fetch == "yes",
                "retmode": args.fetch_retmode,
                "rettype": args.fetch_rettype,
            },
        }
        write_bytes(manifest_path, json.dumps(manifest, indent=2, ensure_ascii=True).encode("utf-8"))
        print(json.dumps(manifest, indent=2, ensure_ascii=True))
        return 0
    except ValueError as exc:
        return fail(str(exc))


def handle_pubmed_review(args: argparse.Namespace) -> int:
    if args.out:
        return fail("pubmed-review writes multiple files; use --out-dir, --records-out, or --manifest-out instead of --out")

    out_dir: Path = args.out_dir
    manifest_path = args.manifest_out or out_dir / "manifest.json"
    records_path = args.records_out or out_dir / "records.json"
    records_jsonl_path = args.records_jsonl_out or out_dir / "records.jsonl"
    search_path = out_dir / "esearch.json"
    summary_path = out_dir / "esummary.json"
    fetch_path = out_dir / "efetch.xml"

    search_params = build_common_params(args)
    search_params["db"] = "pubmed"
    search_params["term"] = args.term
    search_params["retmax"] = str(args.retmax)
    search_params["retstart"] = str(args.retstart)
    search_params["usehistory"] = "y"
    search_params["retmode"] = "json"
    add_optional_param(search_params, "sort", args.sort)
    add_optional_param(search_params, "field", args.field)
    add_optional_param(search_params, "datetype", args.datetype)
    add_optional_param(search_params, "reldate", args.reldate)
    add_optional_param(search_params, "mindate", args.mindate)
    add_optional_param(search_params, "maxdate", args.maxdate)

    summary_template = build_common_params(args)
    summary_template["db"] = "pubmed"
    summary_template["retmode"] = "json"
    add_optional_param(summary_template, "retstart", args.retstart)
    add_optional_param(summary_template, "retmax", args.retmax)
    add_optional_param(summary_template, "version", args.summary_version)
    summary_template["WebEnv"] = "<from esearch>"
    summary_template["query_key"] = "<from esearch>"

    fetch_template = build_common_params(args)
    fetch_template["db"] = "pubmed"
    fetch_template["WebEnv"] = "<from esearch>"
    fetch_template["query_key"] = "<from esearch>"
    add_optional_param(fetch_template, "retstart", args.retstart)
    add_optional_param(fetch_template, "retmax", args.retmax)
    fetch_template["retmode"] = "xml"
    fetch_template["rettype"] = "abstract"

    if args.dry_run:
        plan = {
            "workflow": "pubmed-review",
            "outputs": {
                "search": str(search_path),
                "summary": str(summary_path),
                "fetch": str(fetch_path),
                "records": str(records_path),
                "records_jsonl": str(records_jsonl_path),
                "manifest": str(manifest_path),
            },
            "steps": [
                build_request_plan("esearch", search_params, args, redact=True),
                build_request_plan("esummary", summary_template, args, redact=True),
                build_request_plan("efetch", fetch_template, args, redact=True),
            ],
        }
        print(json.dumps(plan, indent=2, ensure_ascii=True))
        return 0

    try:
        search_payload = request_bytes("esearch", search_params, args)
        search_json = decode_json_bytes(search_payload, "esearch")
        write_bytes(search_path, search_payload)

        search_result = search_json.get("esearchresult")
        if not isinstance(search_result, dict):
            raise ValueError("esearch response is missing 'esearchresult'")

        ids = search_result.get("idlist")
        if not isinstance(ids, list):
            ids = []
        ids = [str(value) for value in ids]

        count_raw = search_result.get("count", "0")
        try:
            total_count = int(str(count_raw))
        except ValueError:
            raise ValueError(f"Unexpected PubMed count value: {count_raw!r}") from None

        webenv = search_result.get("webenv")
        query_key = search_result.get("querykey")
        if total_count > 0 and (not webenv or not query_key):
            raise ValueError("PubMed review expected WebEnv and query_key from esearch but did not receive them")

        extracted_records: list[dict[str, Any]] = []
        summary_path_written: str | None = None
        fetch_path_written: str | None = None

        if total_count > 0:
            summary_params = build_common_params(args)
            summary_params["db"] = "pubmed"
            summary_params["retmode"] = "json"
            summary_params["WebEnv"] = str(webenv)
            summary_params["query_key"] = str(query_key)
            add_optional_param(summary_params, "retstart", args.retstart)
            add_optional_param(summary_params, "retmax", args.retmax)
            add_optional_param(summary_params, "version", args.summary_version)
            summary_payload = request_bytes("esummary", summary_params, args)
            write_bytes(summary_path, summary_payload)
            summary_path_written = str(summary_path)

            fetch_params = build_common_params(args)
            fetch_params["db"] = "pubmed"
            fetch_params["WebEnv"] = str(webenv)
            fetch_params["query_key"] = str(query_key)
            add_optional_param(fetch_params, "retstart", args.retstart)
            add_optional_param(fetch_params, "retmax", args.retmax)
            fetch_params["retmode"] = "xml"
            fetch_params["rettype"] = "abstract"
            fetch_payload = request_bytes("efetch", fetch_params, args)
            write_bytes(fetch_path, fetch_payload)
            fetch_path_written = str(fetch_path)
            extracted_records = parse_pubmed_xml_records(fetch_payload)

        write_json(records_path, extracted_records)
        jsonl_lines = "\n".join(json.dumps(record, ensure_ascii=True) for record in extracted_records)
        write_bytes(records_jsonl_path, (jsonl_lines + ("\n" if jsonl_lines else "")).encode("utf-8"))

        manifest = {
            "workflow": "pubmed-review",
            "term": args.term,
            "total_count": total_count,
            "retstart": args.retstart,
            "retmax": args.retmax,
            "returned_ids": ids,
            "extracted_record_count": len(extracted_records),
            "webenv": webenv,
            "query_key": query_key,
            "paths": {
                "search": str(search_path),
                "summary": summary_path_written,
                "fetch": fetch_path_written,
                "records": str(records_path),
                "records_jsonl": str(records_jsonl_path),
            },
        }
        write_json(manifest_path, manifest)
        print(json.dumps(manifest, indent=2, ensure_ascii=True))
        return 0
    except ValueError as exc:
        return fail(str(exc))


def handle_info(args: argparse.Namespace) -> int:
    params = build_common_params(args)
    add_optional_param(params, "db", args.db)
    add_optional_param(params, "version", args.version)
    add_optional_param(params, "retmode", args.retmode)
    return execute_request("einfo", params, args)


def handle_search(args: argparse.Namespace) -> int:
    params = build_common_params(args)
    params["db"] = args.db
    params["term"] = args.term
    params["retmax"] = str(args.retmax)
    params["retstart"] = str(args.retstart)
    params["usehistory"] = args.usehistory
    params["retmode"] = args.retmode
    add_optional_param(params, "sort", args.sort)
    add_optional_param(params, "field", args.field)
    add_optional_param(params, "idtype", args.idtype)
    add_optional_param(params, "datetype", args.datetype)
    add_optional_param(params, "reldate", args.reldate)
    add_optional_param(params, "mindate", args.mindate)
    add_optional_param(params, "maxdate", args.maxdate)
    return execute_request("esearch", params, args)


def handle_summary(args: argparse.Namespace) -> int:
    ids, has_history = resolve_id_source(args)
    params = build_common_params(args)
    params["db"] = args.db
    params["retmode"] = args.retmode
    add_optional_param(params, "retstart", args.retstart)
    add_optional_param(params, "retmax", args.retmax)
    add_optional_param(params, "version", args.version)
    if ids:
        params["id"] = ids
    if has_history:
        params["WebEnv"] = args.webenv
        params["query_key"] = args.query_key
    return execute_request("esummary", params, args)


def handle_fetch(args: argparse.Namespace) -> int:
    ids, has_history = resolve_id_source(args)
    params = build_common_params(args)
    params["db"] = args.db
    if ids:
        params["id"] = ids
    if has_history:
        params["WebEnv"] = args.webenv
        params["query_key"] = args.query_key
    add_optional_param(params, "retstart", args.retstart)
    add_optional_param(params, "retmax", args.retmax)
    add_optional_param(params, "retmode", args.retmode)
    add_optional_param(params, "rettype", args.rettype)
    add_optional_param(params, "seq_start", args.seq_start)
    add_optional_param(params, "seq_stop", args.seq_stop)
    add_optional_param(params, "strand", args.strand)
    add_optional_param(params, "complexity", args.complexity)
    return execute_request("efetch", params, args)


def handle_link(args: argparse.Namespace) -> int:
    ids, has_history = resolve_id_source(args)
    params = build_common_params(args)
    params["dbfrom"] = args.dbfrom
    add_optional_param(params, "db", args.db)
    add_optional_param(params, "cmd", args.cmd)
    add_optional_param(params, "linkname", args.linkname)
    add_optional_param(params, "term", args.term)
    add_optional_param(params, "holding", args.holding)
    add_optional_param(params, "retmode", args.retmode)
    if ids:
        params["id"] = ids
    if has_history:
        params["WebEnv"] = args.webenv
        params["query_key"] = args.query_key
    return execute_request("elink", params, args)


def handle_post(args: argparse.Namespace) -> int:
    ids: str | None = None
    if args.id_file:
        ids = load_id_file(args.id_file)
    elif args.id:
        ids = normalize_ids(args.id)
    if not ids:
        return fail("Provide --id or --id-file for EPost")

    params = build_common_params(args)
    params["db"] = args.db
    params["id"] = ids
    add_optional_param(params, "WebEnv", args.webenv)
    return execute_request("epost", params, args)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Deterministic wrapper for NCBI Entrez E-utilities.",
    )
    common = argparse.ArgumentParser(add_help=False)
    add_common_request_args(common)

    subparsers = parser.add_subparsers(dest="subcommand", required=True)
    parents = [common]
    build_info_parser(subparsers, parents)
    build_search_parser(subparsers, parents)
    build_summary_parser(subparsers, parents)
    build_fetch_parser(subparsers, parents)
    build_link_parser(subparsers, parents)
    build_post_parser(subparsers, parents)
    build_pubmed_workflow_parser(subparsers, parents)
    build_pubmed_review_parser(subparsers, parents)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.handler(args)
    except ValueError as exc:
        return fail(str(exc))


if __name__ == "__main__":
    sys.exit(main())
