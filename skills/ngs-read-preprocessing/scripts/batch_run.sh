#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# batch_run.sh — ngs-read-preprocessing
# Loops over a sample sheet TSV and calls run.sh per sample.
#
# Sample sheet format (no header, tab-separated):
#   sample_id  fastq_r1  fastq_r2   (fastq_r2 may be empty for SE data)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <sample_sheet.tsv>

Run ngs-read-preprocessing for multiple samples.

Sample sheet (no header, tab-separated):
  sample_id  fastq_r1  fastq_r2   (fastq_r2 empty for single-end data)

Required arguments:
  <sample_sheet.tsv>   Path to the sample sheet TSV file.

Options:
  --outdir-prefix DIR  Base output directory; per-sample dir = DIR/<sample_id>
                       (default: ./results)
  --jobs N             Number of parallel jobs via GNU parallel (default: 1)
  --threads N          Threads passed to each run.sh call (default: 1)
  --extra-args "..."   Extra flags passed verbatim to run.sh
  -h, --help           Show this help message and exit
EOF
}

# --- defaults ---------------------------------------------------------------
OUTDIR_PREFIX="./results"
JOBS=1
THREADS=1
EXTRA_ARGS=""
SAMPLE_SHEET=""

# --- argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --outdir-prefix)  OUTDIR_PREFIX="$2"; shift 2 ;;
    --jobs)           JOBS="$2";          shift 2 ;;
    --threads)        THREADS="$2";       shift 2 ;;
    --extra-args)     EXTRA_ARGS="$2";    shift 2 ;;
    -*)               echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)                SAMPLE_SHEET="$1";  shift ;;
  esac
done

if [[ -z "$SAMPLE_SHEET" ]]; then
  echo "ERROR: sample sheet not specified." >&2
  usage; exit 1
fi

if [[ ! -f "$SAMPLE_SHEET" ]]; then
  echo "ERROR: sample sheet not found: $SAMPLE_SHEET" >&2
  exit 1
fi

# --- count samples ----------------------------------------------------------
TOTAL=$(grep -c $'^[^\t]' "$SAMPLE_SHEET" || true)
echo "[batch] Sample sheet: $SAMPLE_SHEET"
echo "[batch] Total samples: $TOTAL"
echo "[batch] Output prefix: $OUTDIR_PREFIX"
echo "[batch] Parallel jobs: $JOBS"

FAILED=()
IDX=0

# --- worker function (also used by GNU parallel) ----------------------------
run_sample() {
  local sample_id="$1"
  local fastq_r1="$2"
  local fastq_r2="$3"
  local outdir="$4"
  local threads="$5"
  local extra_args="$6"
  local idx="$7"
  local total="$8"
  local script_dir="$9"

  echo "[batch] Processing sample ${idx}/${total}: ${sample_id}"
  mkdir -p "$outdir"

  local cmd=("$script_dir/run.sh" -i "$fastq_r1" --outdir "$outdir"
             --threads "$threads")
  [[ -n "$fastq_r2" ]] && cmd+=(-I "$fastq_r2")
  [[ -n "$extra_args" ]] && cmd+=($extra_args)

  if ! "${cmd[@]}"; then
    echo "[batch] ERROR: sample ${sample_id} failed." >&2
    return 1
  fi
}

export -f run_sample

# --- run samples ------------------------------------------------------------
if [[ "$JOBS" -gt 1 ]] && command -v parallel &>/dev/null; then
  echo "[batch] Using GNU parallel with $JOBS jobs."

  while IFS=$'\t' read -r sample_id fastq_r1 fastq_r2 _rest; do
    [[ -z "$sample_id" || "$sample_id" == \#* ]] && continue
    IDX=$((IDX + 1))
    outdir="${OUTDIR_PREFIX}/${sample_id}"
    echo "$sample_id"$'\t'"$fastq_r1"$'\t'"${fastq_r2:-}"$'\t'"$outdir"$'\t'"$THREADS"$'\t'"$EXTRA_ARGS"$'\t'"$IDX"$'\t'"$TOTAL"$'\t'"$SCRIPT_DIR"
  done < "$SAMPLE_SHEET" | \
  parallel --jobs "$JOBS" --colsep $'\t' \
    run_sample {1} {2} {3} {4} {5} {6} {7} {8} {9} \
    || FAILED+=("parallel-batch")

else
  while IFS=$'\t' read -r sample_id fastq_r1 fastq_r2 _rest; do
    [[ -z "$sample_id" || "$sample_id" == \#* ]] && continue
    IDX=$((IDX + 1))
    outdir="${OUTDIR_PREFIX}/${sample_id}"
    echo "[batch] Processing sample ${IDX}/${TOTAL}: ${sample_id}"
    mkdir -p "$outdir"

    cmd=("$SCRIPT_DIR/run.sh" -i "$fastq_r1" --outdir "$outdir"
         --threads "$THREADS")
    [[ -n "${fastq_r2:-}" ]] && cmd+=(-I "$fastq_r2")
    [[ -n "$EXTRA_ARGS" ]] && cmd+=($EXTRA_ARGS)

    if ! "${cmd[@]}"; then
      echo "[batch] ERROR: sample ${sample_id} failed." >&2
      FAILED+=("$sample_id")
    fi
  done < "$SAMPLE_SHEET"
fi

# --- summary ----------------------------------------------------------------
NFAILED=${#FAILED[@]}
NCOMPLETED=$((TOTAL - NFAILED))
echo ""
echo "[batch] ----------------------------------------"
echo "[batch] Completed: ${NCOMPLETED}/${TOTAL}, Failed: ${NFAILED}"
if [[ $NFAILED -gt 0 ]]; then
  echo "[batch] Failed samples:"
  for s in "${FAILED[@]}"; do
    echo "[batch]   - $s"
  done
  exit 1
fi
