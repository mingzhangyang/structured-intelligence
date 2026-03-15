#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# batch_run.sh — rnaseq-read-counting
# Collects BAM files from a sample sheet and calls run.sh ONCE on all samples
# together, producing a single count matrix (featureCounts multi-sample mode).
#
# Sample sheet format (no header, tab-separated):
#   sample_id  bam  gtf
#
# Note: featureCounts accepts all BAMs in one call. This batch script collects
# all BAM paths and invokes run.sh a single time with all BAMs, rather than
# once per sample. The GTF must be the same for all rows; the value from the
# first non-comment row is used, and a warning is printed if rows differ.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <sample_sheet.tsv>

Run rnaseq-read-counting across multiple samples.

featureCounts can process all BAMs in a single invocation to produce one
count matrix. This script collects every BAM from the sample sheet and
calls run.sh once with all of them.

Sample sheet (no header, tab-separated):
  sample_id  bam  gtf   (gtf must be identical across all rows)

Required arguments:
  <sample_sheet.tsv>   Path to the sample sheet TSV file.

Options:
  --outdir-prefix DIR  Base output directory for the combined matrix
                       (default: ./results/all_samples)
  --threads N          Threads passed to run.sh (default: 1)
  --extra-args "..."   Extra flags passed verbatim to run.sh
  -h, --help           Show this help message and exit

Note: --jobs is not applicable here because run.sh is called only once.
EOF
}

# --- defaults ---------------------------------------------------------------
OUTDIR_PREFIX="./results"
THREADS=1
EXTRA_ARGS=""
SAMPLE_SHEET=""

# --- argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --outdir-prefix)  OUTDIR_PREFIX="$2"; shift 2 ;;
    --jobs)           echo "[batch] NOTE: --jobs is ignored for rnaseq-read-counting (single featureCounts call)." ; shift 2 ;;
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

# --- parse sample sheet: collect BAMs and verify GTF consistency ------------
ALL_BAMS=()
ALL_SAMPLE_IDS=()
GTF=""
IDX=0

while IFS=$'\t' read -r sample_id bam gtf_col _rest; do
  [[ -z "$sample_id" || "$sample_id" == \#* ]] && continue
  IDX=$((IDX + 1))
  ALL_SAMPLE_IDS+=("$sample_id")
  ALL_BAMS+=("$bam")

  if [[ -z "$GTF" ]]; then
    GTF="$gtf_col"
  elif [[ "$GTF" != "$gtf_col" ]]; then
    echo "[batch] WARNING: GTF differs for sample ${sample_id} ('${gtf_col}' vs '${GTF}'). Using first value." >&2
  fi
done < "$SAMPLE_SHEET"

TOTAL=${#ALL_SAMPLE_IDS[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo "ERROR: no samples found in sample sheet." >&2
  exit 1
fi

if [[ -z "$GTF" ]]; then
  echo "ERROR: GTF path is empty in sample sheet." >&2
  exit 1
fi

echo "[batch] Sample sheet: $SAMPLE_SHEET"
echo "[batch] Total samples (BAMs): $TOTAL"
echo "[batch] GTF: $GTF"
echo "[batch] Output prefix: $OUTDIR_PREFIX"
echo "[batch] BAMs collected:"
for b in "${ALL_BAMS[@]}"; do
  echo "[batch]   $b"
done

# --- single featureCounts call via run.sh -----------------------------------
OUTDIR="${OUTDIR_PREFIX}/all_samples"
mkdir -p "$OUTDIR"

echo ""
echo "[batch] Processing sample 1/${TOTAL}: (all samples combined)"
echo "[batch] Running featureCounts on all ${TOTAL} BAMs together..."

cmd=("$SCRIPT_DIR/run.sh"
     --gtf "$GTF"
     --outdir "$OUTDIR"
     --threads "$THREADS")
# Append all BAMs
for bam in "${ALL_BAMS[@]}"; do
  cmd+=(--bam "$bam")
done
[[ -n "$EXTRA_ARGS" ]] && cmd+=($EXTRA_ARGS)

FAILED=()
if ! "${cmd[@]}"; then
  echo "[batch] ERROR: combined featureCounts run failed." >&2
  FAILED+=("all_samples")
fi

# --- summary ----------------------------------------------------------------
NFAILED=${#FAILED[@]}
NCOMPLETED=$(( NFAILED == 0 ? 1 : 0 ))
echo ""
echo "[batch] ----------------------------------------"
echo "[batch] Samples in sheet: ${TOTAL}, featureCounts run: 1 (combined)"
echo "[batch] Completed: ${NCOMPLETED}/1, Failed: ${NFAILED}"
if [[ $NFAILED -gt 0 ]]; then
  echo "[batch] Failed runs:"
  for s in "${FAILED[@]}"; do
    echo "[batch]   - $s"
  done
  exit 1
fi
