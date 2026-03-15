#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# batch_run.sh — rnaseq-differential-expression
# Runs multiple contrasts from a contrast sheet, calling run.sh per contrast.
#
# This skill is NOT per-sample — it operates on the full count matrix.
# This batch script iterates over contrasts defined in a TSV.
#
# Contrast sheet format (no header, tab-separated):
#   contrast_label  condition_a  condition_b
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <contrast_sheet.tsv>

Run rnaseq-differential-expression for multiple contrasts.

Contrast sheet (no header, tab-separated):
  contrast_label  condition_a  condition_b

Required arguments:
  <contrast_sheet.tsv>   Path to the contrast sheet TSV file.
  --counts FILE          Path to the counts matrix (required).
  --metadata FILE        Path to the sample metadata file (required).

Options:
  --outdir-prefix DIR    Base output directory; per-contrast dir = DIR/<contrast_label>
                         (default: ./results)
  --jobs N               Number of parallel jobs via GNU parallel (default: 1)
  --threads N            Threads passed to each run.sh call (default: 1)
  --extra-args "..."     Extra flags passed verbatim to run.sh
  -h, --help             Show this help message and exit
EOF
}

# --- defaults ---------------------------------------------------------------
OUTDIR_PREFIX="./results"
JOBS=1
THREADS=1
EXTRA_ARGS=""
CONTRAST_SHEET=""
COUNTS=""
METADATA=""

# --- argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --outdir-prefix)  OUTDIR_PREFIX="$2"; shift 2 ;;
    --jobs)           JOBS="$2";          shift 2 ;;
    --threads)        THREADS="$2";       shift 2 ;;
    --extra-args)     EXTRA_ARGS="$2";    shift 2 ;;
    --counts)         COUNTS="$2";        shift 2 ;;
    --metadata)       METADATA="$2";      shift 2 ;;
    -*)               echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)                CONTRAST_SHEET="$1"; shift ;;
  esac
done

if [[ -z "$CONTRAST_SHEET" ]]; then
  echo "ERROR: contrast sheet not specified." >&2
  usage; exit 1
fi
if [[ -z "$COUNTS" ]]; then
  echo "ERROR: --counts is required." >&2
  usage; exit 1
fi
if [[ -z "$METADATA" ]]; then
  echo "ERROR: --metadata is required." >&2
  usage; exit 1
fi
if [[ ! -f "$CONTRAST_SHEET" ]]; then
  echo "ERROR: contrast sheet not found: $CONTRAST_SHEET" >&2
  exit 1
fi
if [[ ! -f "$COUNTS" ]]; then
  echo "ERROR: counts file not found: $COUNTS" >&2
  exit 1
fi
if [[ ! -f "$METADATA" ]]; then
  echo "ERROR: metadata file not found: $METADATA" >&2
  exit 1
fi

# --- count contrasts --------------------------------------------------------
TOTAL=$(grep -c $'^[^\t]' "$CONTRAST_SHEET" || true)
echo "[batch] Contrast sheet: $CONTRAST_SHEET"
echo "[batch] Counts: $COUNTS"
echo "[batch] Metadata: $METADATA"
echo "[batch] Total contrasts: $TOTAL"
echo "[batch] Output prefix: $OUTDIR_PREFIX"
echo "[batch] Parallel jobs: $JOBS"

FAILED=()
IDX=0

# --- worker function (also used by GNU parallel) ----------------------------
run_contrast() {
  local contrast_label="$1"
  local condition_a="$2"
  local condition_b="$3"
  local counts="$4"
  local metadata="$5"
  local outdir="$6"
  local threads="$7"
  local extra_args="$8"
  local idx="$9"
  local total="${10}"
  local script_dir="${11}"

  echo "[batch] Processing sample ${idx}/${total}: ${contrast_label}"
  mkdir -p "$outdir"

  local cmd=("$script_dir/run.sh"
             --counts "$counts"
             --metadata "$metadata"
             --contrast "${condition_a},${condition_b}"
             --outdir "$outdir"
             --threads "$threads")
  [[ -n "$extra_args" ]] && cmd+=($extra_args)

  if ! "${cmd[@]}"; then
    echo "[batch] ERROR: contrast ${contrast_label} failed." >&2
    return 1
  fi
}

export -f run_contrast

# --- run contrasts ----------------------------------------------------------
if [[ "$JOBS" -gt 1 ]] && command -v parallel &>/dev/null; then
  echo "[batch] Using GNU parallel with $JOBS jobs."

  while IFS=$'\t' read -r contrast_label condition_a condition_b _rest; do
    [[ -z "$contrast_label" || "$contrast_label" == \#* ]] && continue
    IDX=$((IDX + 1))
    outdir="${OUTDIR_PREFIX}/${contrast_label}"
    echo "$contrast_label"$'\t'"$condition_a"$'\t'"$condition_b"$'\t'"$COUNTS"$'\t'"$METADATA"$'\t'"$outdir"$'\t'"$THREADS"$'\t'"$EXTRA_ARGS"$'\t'"$IDX"$'\t'"$TOTAL"$'\t'"$SCRIPT_DIR"
  done < "$CONTRAST_SHEET" | \
  parallel --jobs "$JOBS" --colsep $'\t' \
    run_contrast {1} {2} {3} {4} {5} {6} {7} {8} {9} {10} {11} \
    || FAILED+=("parallel-batch")

else
  while IFS=$'\t' read -r contrast_label condition_a condition_b _rest; do
    [[ -z "$contrast_label" || "$contrast_label" == \#* ]] && continue
    IDX=$((IDX + 1))
    outdir="${OUTDIR_PREFIX}/${contrast_label}"
    echo "[batch] Processing sample ${IDX}/${TOTAL}: ${contrast_label}"
    mkdir -p "$outdir"

    cmd=("$SCRIPT_DIR/run.sh"
         --counts "$COUNTS"
         --metadata "$METADATA"
         --contrast "${condition_a},${condition_b}"
         --outdir "$outdir"
         --threads "$THREADS")
    [[ -n "$EXTRA_ARGS" ]] && cmd+=($EXTRA_ARGS)

    if ! "${cmd[@]}"; then
      echo "[batch] ERROR: contrast ${contrast_label} failed." >&2
      FAILED+=("$contrast_label")
    fi
  done < "$CONTRAST_SHEET"
fi

# --- summary ----------------------------------------------------------------
NFAILED=${#FAILED[@]}
NCOMPLETED=$((TOTAL - NFAILED))
echo ""
echo "[batch] ----------------------------------------"
echo "[batch] Completed: ${NCOMPLETED}/${TOTAL}, Failed: ${NFAILED}"
if [[ $NFAILED -gt 0 ]]; then
  echo "[batch] Failed contrasts:"
  for s in "${FAILED[@]}"; do
    echo "[batch]   - $s"
  done
  exit 1
fi
