#!/usr/bin/env bash
set -euo pipefail

# rnaseq-differential-expression: Dispatches to DESeq2 or edgeR R scripts for DE analysis

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Input (one of the following):
  --counts FILE           Count matrix (TSV: gene IDs as rows, samples as columns)
  --quant-dirs FILE       Quant directory manifest (TSV: sample_id<TAB>path_to_quant_dir)
                          for Salmon or kallisto output (uses tximport internally)
  --tx2gene FILE          Transcript-to-gene mapping (TSV: tx_id<TAB>gene_id, no header)
                          Required when --quant-dirs is used
  --metadata FILE         Sample metadata (TSV: sample_id, condition, [batch])

Optional:
  --tool STR              DE tool: deseq2 or edger (default: deseq2)
  --quant-type STR        Quantifier type: salmon or kallisto (default: salmon)
                          Used only with --quant-dirs
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
QUANT_DIRS=""
TX2GENE=""
QUANT_TYPE="salmon"
METADATA=""
TOOL="deseq2"
CONTRAST=""
FDR=0.05
LFC=1
OUTDIR="./de_output"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --counts)      COUNTS="$2"; shift 2 ;;
    --quant-dirs)  QUANT_DIRS="$2"; shift 2 ;;
    --tx2gene)     TX2GENE="$2"; shift 2 ;;
    --quant-type)  QUANT_TYPE="$2"; shift 2 ;;
    --metadata)    METADATA="$2"; shift 2 ;;
    --tool)        TOOL="$2"; shift 2 ;;
    --contrast)    CONTRAST="$2"; shift 2 ;;
    --fdr)         FDR="$2"; shift 2 ;;
    --lfc)         LFC="$2"; shift 2 ;;
    --outdir)      OUTDIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             echo "Error: unknown option $1" >&2; usage ;;
  esac
done

# Validate: require exactly one of --counts or --quant-dirs
if [[ -z "$COUNTS" && -z "$QUANT_DIRS" ]]; then
  echo "Error: either --counts or --quant-dirs is required." >&2
  usage
fi
if [[ -n "$COUNTS" && -n "$QUANT_DIRS" ]]; then
  echo "Error: --counts and --quant-dirs are mutually exclusive." >&2
  usage
fi
if [[ -z "$METADATA" ]]; then
  echo "Error: --metadata is required." >&2
  usage
fi
if [[ -n "$COUNTS" && ! -f "$COUNTS" ]]; then
  echo "Error: count matrix not found: $COUNTS" >&2
  exit 1
fi
if [[ -n "$QUANT_DIRS" && ! -f "$QUANT_DIRS" ]]; then
  echo "Error: quant-dirs manifest not found: $QUANT_DIRS" >&2
  exit 1
fi
if [[ -n "$QUANT_DIRS" && -z "$TX2GENE" ]]; then
  echo "Error: --tx2gene is required when using --quant-dirs." >&2
  usage
fi
if [[ -n "$TX2GENE" && ! -f "$TX2GENE" ]]; then
  echo "Error: tx2gene file not found: $TX2GENE" >&2
  exit 1
fi
if [[ ! -f "$METADATA" ]]; then
  echo "Error: metadata file not found: $METADATA" >&2
  exit 1
fi

mkdir -p "$OUTDIR"

echo "=== RNA-seq Differential Expression ==="
echo "Tool:      $TOOL"
if [[ -n "$COUNTS" ]]; then
  echo "Input:     count matrix: $COUNTS"
else
  echo "Input:     quant dirs: $QUANT_DIRS (type: $QUANT_TYPE)"
  echo "tx2gene:   $TX2GENE"
fi
echo "Metadata:  $METADATA"
echo "Contrast:  ${CONTRAST:-auto (first two levels of condition)}"
echo "FDR:       $FDR"
echo "LFC:       $LFC"
echo "Output:    $OUTDIR"

# Build R script arguments
R_ARGS=(
  --metadata "$METADATA"
  --fdr "$FDR"
  --lfc "$LFC"
  --outdir "$OUTDIR"
)

if [[ -n "$COUNTS" ]]; then
  R_ARGS+=(--counts "$COUNTS")
else
  R_ARGS+=(--quant-dirs "$QUANT_DIRS" --tx2gene "$TX2GENE" --quant-type "$QUANT_TYPE")
fi

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
