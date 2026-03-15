#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") [--outdir DIR] [--threads N] [--multiqc-config FILE] FASTQ [FASTQ ...]"
    echo ""
    echo "Run FastQC on input FASTQ files and aggregate with MultiQC."
    echo ""
    echo "Options:"
    echo "  --outdir DIR           Output directory (default: fastqc_results)"
    echo "  --threads N            Number of parallel threads for FastQC (default: 4)"
    echo "  --multiqc-config FILE  Custom MultiQC configuration file"
    echo "  -h, --help             Show this help message"
    exit "${1:-0}"
}

OUTDIR="fastqc_results"
THREADS=4
MULTIQC_CONFIG=""
FASTQS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --multiqc-config) MULTIQC_CONFIG="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) FASTQS+=("$1"); shift ;;
    esac
done

if [[ ${#FASTQS[@]} -eq 0 ]]; then
    echo "Error: No FASTQ files specified." >&2
    usage 1
fi

mkdir -p "$OUTDIR"

echo "==> Running FastQC on ${#FASTQS[@]} file(s) with $THREADS threads..."
fastqc --outdir "$OUTDIR" --threads "$THREADS" "${FASTQS[@]}"

echo "==> Running MultiQC to aggregate reports..."
MULTIQC_ARGS=("$OUTDIR" --outdir "$OUTDIR/multiqc" --force)
if [[ -n "$MULTIQC_CONFIG" ]]; then
    MULTIQC_ARGS+=(--config "$MULTIQC_CONFIG")
fi
multiqc "${MULTIQC_ARGS[@]}"

echo "==> QC complete."
echo "FastQC reports: $OUTDIR/"
echo "MultiQC report: $OUTDIR/multiqc/multiqc_report.html"
