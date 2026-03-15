#!/usr/bin/env bash
set -euo pipefail

# rnaseq-functional-enrichment: Dispatches to clusterProfiler (R) or gseapy (Python)
# for GO, KEGG, and Reactome enrichment analysis.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Input (one required):
  --de-results FILE       DE results TSV (must contain gene_id and padj columns)
  --ranked-list FILE      Pre-ranked gene list TSV (gene_id, score; alternative to --de-results)

Tool:
  --tool STR              clusterProfiler or gseapy (default: clusterProfiler)

Analysis:
  --analysis STR          ora or gsea (default: ora if --de-results; gsea if --ranked-list)
  --organism STR          KEGG organism code: hsa, mmu, rno, dre (default: hsa)
  --gene-id-type STR      SYMBOL, ENSEMBL, or ENTREZID (default: SYMBOL)
  --databases STR         Comma-separated list: go,kegg,reactome (default: go,kegg)
  --fdr FLOAT             FDR cutoff for ORA significance and result filtering (default: 0.05)
  --min-gs-size INT       Minimum gene set size (default: 5)
  --max-gs-size INT       Maximum gene set size (default: 500)
  --outdir DIR            Output directory (default: enrichment_results)

  -h, --help              Show this help message

Examples:
  $(basename "$0") --de-results de_results.tsv --tool clusterProfiler
  $(basename "$0") --de-results de_results.tsv --tool gseapy --databases go,kegg,reactome
  $(basename "$0") --ranked-list ranked_genes.tsv --analysis gsea --organism mmu
EOF
  exit 1
}

# --- Defaults ---
DE_RESULTS=""
RANKED_LIST=""
TOOL="clusterProfiler"
ANALYSIS=""
ORGANISM="hsa"
GENE_ID_TYPE="SYMBOL"
DATABASES="go,kegg"
FDR=0.05
MIN_GS_SIZE=5
MAX_GS_SIZE=500
OUTDIR="enrichment_results"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --de-results)    DE_RESULTS="$2";    shift 2 ;;
    --ranked-list)   RANKED_LIST="$2";   shift 2 ;;
    --tool)          TOOL="$2";          shift 2 ;;
    --analysis)      ANALYSIS="$2";      shift 2 ;;
    --organism)      ORGANISM="$2";      shift 2 ;;
    --gene-id-type)  GENE_ID_TYPE="$2";  shift 2 ;;
    --databases)     DATABASES="$2";     shift 2 ;;
    --fdr)           FDR="$2";           shift 2 ;;
    --min-gs-size)   MIN_GS_SIZE="$2";   shift 2 ;;
    --max-gs-size)   MAX_GS_SIZE="$2";   shift 2 ;;
    --outdir)        OUTDIR="$2";        shift 2 ;;
    -h|--help)       usage ;;
    *) echo "Error: unknown option '$1'" >&2; usage ;;
  esac
done

# --- Validate inputs ---
if [[ -z "$DE_RESULTS" && -z "$RANKED_LIST" ]]; then
  echo "Error: one of --de-results or --ranked-list is required." >&2
  usage
fi

if [[ -n "$DE_RESULTS" && -n "$RANKED_LIST" ]]; then
  echo "Error: --de-results and --ranked-list are mutually exclusive." >&2
  usage
fi

if [[ -n "$DE_RESULTS" && ! -f "$DE_RESULTS" ]]; then
  echo "Error: DE results file not found: $DE_RESULTS" >&2
  exit 1
fi

if [[ -n "$RANKED_LIST" && ! -f "$RANKED_LIST" ]]; then
  echo "Error: Ranked list file not found: $RANKED_LIST" >&2
  exit 1
fi

# --- Infer analysis type if not set ---
if [[ -z "$ANALYSIS" ]]; then
  if [[ -n "$DE_RESULTS" ]]; then
    ANALYSIS="ora"
  else
    ANALYSIS="gsea"
  fi
fi

# --- Validate tool ---
if [[ "$TOOL" != "clusterProfiler" && "$TOOL" != "gseapy" ]]; then
  echo "Error: --tool must be 'clusterProfiler' or 'gseapy', got '$TOOL'." >&2
  exit 1
fi

# --- Validate analysis ---
if [[ "$ANALYSIS" != "ora" && "$ANALYSIS" != "gsea" ]]; then
  echo "Error: --analysis must be 'ora' or 'gsea', got '$ANALYSIS'." >&2
  exit 1
fi

# --- Validate organism ---
VALID_ORGS=("hsa" "mmu" "rno" "dre")
VALID=0
for o in "${VALID_ORGS[@]}"; do
  [[ "$ORGANISM" == "$o" ]] && VALID=1 && break
done
if [[ "$VALID" -eq 0 ]]; then
  echo "Error: --organism must be one of: hsa, mmu, rno, dre. Got '$ORGANISM'." >&2
  exit 1
fi

mkdir -p "$OUTDIR"

# --- Print run summary ---
echo "=== RNA-seq Functional Enrichment ==="
echo "Tool:          $TOOL"
echo "Analysis:      $ANALYSIS"
echo "Organism:      $ORGANISM"
echo "Gene ID type:  $GENE_ID_TYPE"
echo "Databases:     $DATABASES"
echo "FDR cutoff:    $FDR"
echo "Gene set size: $MIN_GS_SIZE – $MAX_GS_SIZE"
echo "Output:        $OUTDIR"
if [[ -n "$DE_RESULTS" ]]; then
  echo "Input:         $DE_RESULTS (DE results)"
else
  echo "Input:         $RANKED_LIST (ranked gene list)"
fi
echo ""

# --- Dispatch ---
if [[ "$TOOL" == "clusterProfiler" ]]; then
  R_SCRIPT="${SCRIPT_DIR}/run_enrichment.R"
  if [[ ! -f "$R_SCRIPT" ]]; then
    echo "Error: R script not found at $R_SCRIPT" >&2
    exit 1
  fi

  R_ARGS=(
    --analysis      "$ANALYSIS"
    --organism      "$ORGANISM"
    --gene-id-type  "$GENE_ID_TYPE"
    --databases     "$DATABASES"
    --fdr           "$FDR"
    --min-gs-size   "$MIN_GS_SIZE"
    --max-gs-size   "$MAX_GS_SIZE"
    --outdir        "$OUTDIR"
  )
  if [[ -n "$DE_RESULTS" ]]; then
    R_ARGS+=(--de-results "$DE_RESULTS")
  else
    R_ARGS+=(--ranked-list "$RANKED_LIST")
  fi

  echo "--- Dispatching to clusterProfiler (R) ---"
  Rscript "$R_SCRIPT" "${R_ARGS[@]}"

elif [[ "$TOOL" == "gseapy" ]]; then
  PY_SCRIPT="${SCRIPT_DIR}/run_enrichment.py"
  if [[ ! -f "$PY_SCRIPT" ]]; then
    echo "Error: Python script not found at $PY_SCRIPT" >&2
    exit 1
  fi

  PY_ARGS=(
    --analysis      "$ANALYSIS"
    --organism      "$ORGANISM"
    --gene-id-type  "$GENE_ID_TYPE"
    --databases     "$DATABASES"
    --fdr           "$FDR"
    --min-gs-size   "$MIN_GS_SIZE"
    --max-gs-size   "$MAX_GS_SIZE"
    --outdir        "$OUTDIR"
  )
  if [[ -n "$DE_RESULTS" ]]; then
    PY_ARGS+=(--de-results "$DE_RESULTS")
  else
    PY_ARGS+=(--ranked-list "$RANKED_LIST")
  fi

  echo "--- Dispatching to gseapy (Python) ---"
  python3 "$PY_SCRIPT" "${PY_ARGS[@]}"
fi

echo ""
echo "=== Functional enrichment analysis complete ==="
echo "Output directory: $OUTDIR"
