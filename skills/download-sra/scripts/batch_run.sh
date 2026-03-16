#!/usr/bin/env bash
# batch_run.sh — run download-sra for each accession in a file using GNU parallel
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$SCRIPT_DIR/run.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <ACCESSIONS_FILE> [--jobs N] [-- RUN_OPTIONS...]

Batch-download SRA accessions in parallel.

Arguments:
  ACCESSIONS_FILE   One SRR (or SRP/PRJNA) accession per line

Options:
  --jobs N          Number of concurrent downloads (default: 2)
  -- OPTIONS        Additional options forwarded to run.sh (e.g. --outdir, --threads)
  -h, --help        Show this help
EOF
    exit "${1:-0}"
}

JOBS=2
ACC_FILE=""
RUN_OPTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs)   JOBS="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        --)       shift; RUN_OPTS=("$@"); break ;;
        *)        ACC_FILE="$1"; shift ;;
    esac
done

if [[ -z "$ACC_FILE" || ! -f "$ACC_FILE" ]]; then
    echo "Error: ACCESSIONS_FILE is required and must exist." >&2
    usage 1
fi

if ! command -v parallel &>/dev/null; then
    echo "GNU parallel not found; running sequentially." >&2
    while IFS= read -r acc || [[ -n "$acc" ]]; do
        [[ -z "$acc" || "$acc" == \#* ]] && continue
        bash "$RUN_SCRIPT" "$acc" "${RUN_OPTS[@]}"
    done < "$ACC_FILE"
else
    grep -v '^#' "$ACC_FILE" | grep -v '^$' | \
        parallel -j "$JOBS" bash "$RUN_SCRIPT" {} "${RUN_OPTS[@]}"
fi
