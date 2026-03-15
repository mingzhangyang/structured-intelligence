#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") -i READ1 [-I READ2] [--outdir DIR] [--threads N] [OPTIONS]"
    echo ""
    echo "Trim adapters and filter reads with fastp."
    echo ""
    echo "Options:"
    echo "  -i FILE        Input FASTQ R1 (required)"
    echo "  -I FILE        Input FASTQ R2 (paired-end)"
    echo "  --outdir DIR   Output directory (default: fastp_results)"
    echo "  --threads N    Worker threads (default: 4)"
    echo "  --min-qual N   Qualified quality value (default: 15)"
    echo "  --min-len N    Minimum read length after trimming (default: 36)"
    echo "  --polyg        Enable polyG tail trimming (NextSeq/NovaSeq)"
    echo "  -h, --help     Show this help message"
    exit "${1:-0}"
}

READ1=""
READ2=""
OUTDIR="fastp_results"
THREADS=4
MIN_QUAL=15
MIN_LEN=36
POLYG=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i) READ1="$2"; shift 2 ;;
        -I) READ2="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --min-qual) MIN_QUAL="$2"; shift 2 ;;
        --min-len) MIN_LEN="$2"; shift 2 ;;
        --polyg) POLYG="--poly_g_min_len 10"; shift ;;
        -h|--help) usage 0 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

if [[ -z "$READ1" ]]; then
    echo "Error: -i READ1 is required." >&2
    usage 1
fi

mkdir -p "$OUTDIR"

BASENAME=$(basename "$READ1" | sed 's/\.\(fastq\|fq\)\(\.gz\)\?$//')
FASTP_ARGS=(
    --in1 "$READ1"
    --out1 "$OUTDIR/${BASENAME}_trimmed.fastq.gz"
    --json "$OUTDIR/${BASENAME}_fastp.json"
    --html "$OUTDIR/${BASENAME}_fastp.html"
    --qualified_quality_phred "$MIN_QUAL"
    --length_required "$MIN_LEN"
    --thread "$THREADS"
)

if [[ -n "$READ2" ]]; then
    BASENAME2=$(basename "$READ2" | sed 's/\.\(fastq\|fq\)\(\.gz\)\?$//')
    FASTP_ARGS+=(--in2 "$READ2" --out2 "$OUTDIR/${BASENAME2}_trimmed.fastq.gz")
fi

if [[ -n "$POLYG" ]]; then
    FASTP_ARGS+=($POLYG)
fi

FASTP_ARGS+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

echo "==> Running fastp..."
fastp "${FASTP_ARGS[@]}"

echo "==> Preprocessing complete."
echo "Output: $OUTDIR/"
echo "Report: $OUTDIR/${BASENAME}_fastp.html"
