#!/usr/bin/env bash
set -euo pipefail

# rnaseq-differential-expression: Dispatches to DESeq2 or edgeR R scripts for DE analysis

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required:
  --counts FILE           Count matrix (TSV: gene IDs as rows, samples as columns)
  --metadata FILE         Sample metadata (TSV: sample_id, condition, [batch])

Optional:
  --tool STR              DE tool: deseq2 or edger (default: deseq2)
  --contrast STR          Condition levels to compare, comma-separated (e.g., treated,control)
  --fdr FLOAT             FDR threshold (default: 0.05)
  --lfc FLOAT             log2 fold-change threshold (default: 1)
  --outdir DIR            Output directory (default: ./de_output)
  -h, --help              Show this help message
EOF
  exit 1
}

# Defaults
COUNTS=""
METADATA=""
TOOL="deseq2"
CONTRAST=""
FDR=0.05
LFC=1
OUTDIR="./de_output"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --counts)    COUNTS="$2"; shift 2 ;;
    --metadata)  METADATA="$2"; shift 2 ;;
    --tool)      TOOL="$2"; shift 2 ;;
    --contrast)  CONTRAST="$2"; shift 2 ;;
    --fdr)       FDR="$2"; shift 2 ;;
    --lfc)       LFC="$2"; shift 2 ;;
    --outdir)    OUTDIR="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *)           echo "Error: unknown option $1" >&2; usage ;;
  esac
done

# Validate required arguments
if [[ -z "$COUNTS" ]]; then
  echo "Error: --counts is required." >&2
  usage
fi
if [[ -z "$METADATA" ]]; then
  echo "Error: --metadata is required." >&2
  usage
fi
if [[ ! -f "$COUNTS" ]]; then
  echo "Error: count matrix not found: $COUNTS" >&2
  exit 1
fi
if [[ ! -f "$METADATA" ]]; then
  echo "Error: metadata file not found: $METADATA" >&2
  exit 1
fi

mkdir -p "$OUTDIR"

echo "=== RNA-seq Differential Expression ==="
echo "Tool:      $TOOL"
echo "Counts:    $COUNTS"
echo "Metadata:  $METADATA"
echo "Contrast:  ${CONTRAST:-auto (first two levels of condition)}"
echo "FDR:       $FDR"
echo "LFC:       $LFC"
echo "Output:    $OUTDIR"

# Build R script arguments
R_ARGS=(
  --counts "$COUNTS"
  --metadata "$METADATA"
  --fdr "$FDR"
  --lfc "$LFC"
  --outdir "$OUTDIR"
)

if [[ -n "$CONTRAST" ]]; then
  R_ARGS+=(--contrast "$CONTRAST")
fi

if [[ "$TOOL" == "deseq2" ]]; then
  R_SCRIPT="${SCRIPT_DIR}/run_deseq2.R"
  if [[ ! -f "$R_SCRIPT" ]]; then
    echo "Error: DESeq2 R script not found at $R_SCRIPT" >&2
    exit 1
  fi

  echo "--- Dispatching to DESeq2 ---"
  Rscript "$R_SCRIPT" "${R_ARGS[@]}"

elif [[ "$TOOL" == "edger" ]]; then
  R_SCRIPT="${SCRIPT_DIR}/run_edger.R"
  if [[ ! -f "$R_SCRIPT" ]]; then
    echo "Error: edgeR R script not found at $R_SCRIPT" >&2
    exit 1
  fi

  echo "--- Dispatching to edgeR ---"
  Rscript "$R_SCRIPT" "${R_ARGS[@]}"

else
  echo "Error: unknown tool '$TOOL'. Choose 'deseq2' or 'edger'." >&2
  exit 1
fi

echo ""
echo "=== Differential expression analysis complete ==="
echo "Output directory: $OUTDIR"
