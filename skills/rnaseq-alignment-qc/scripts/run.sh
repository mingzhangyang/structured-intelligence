#!/usr/bin/env bash
set -euo pipefail

# rnaseq-alignment-qc: RNA-seq alignment quality assessment using RSeQC and Qualimap

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required:
  --bam FILE              Coordinate-sorted BAM file (with .bai index)

Optional:
  --bed FILE              BED file of gene models (for RSeQC)
  --gtf FILE              GTF annotation file (for Qualimap)
  --outdir DIR            Output directory (default: ./alignment_qc_output)
  -h, --help              Show this help message
EOF
  exit 1
}

# Defaults
BAM=""
BED=""
GTF=""
OUTDIR="./alignment_qc_output"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bam)    BAM="$2"; shift 2 ;;
    --bed)    BED="$2"; shift 2 ;;
    --gtf)    GTF="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)        echo "Error: unknown option $1" >&2; usage ;;
  esac
done

# Validate required arguments
if [[ -z "$BAM" ]]; then
  echo "Error: --bam is required." >&2
  usage
fi
if [[ ! -f "$BAM" ]]; then
  echo "Error: BAM file not found: $BAM" >&2
  exit 1
fi

# Check for BAM index
if [[ ! -f "${BAM}.bai" ]] && [[ ! -f "${BAM%.bam}.bai" ]]; then
  echo "Warning: BAM index not found. Attempting to create index..."
  samtools index "$BAM"
fi

mkdir -p "$OUTDIR"

RSEQC_DIR="${OUTDIR}/rseqc"
QUALIMAP_DIR="${OUTDIR}/qualimap"
mkdir -p "$RSEQC_DIR"

SAMPLE_NAME=$(basename "$BAM" .bam)
SUMMARY_FILE="${OUTDIR}/qc_summary.txt"

echo "=== RNA-seq Alignment QC ==="
echo "BAM:    $BAM"
echo "BED:    ${BED:-not provided}"
echo "GTF:    ${GTF:-not provided}"
echo "Output: $OUTDIR"
echo ""

# Initialize summary
echo "=== RNA-seq Alignment QC Summary ===" > "$SUMMARY_FILE"
echo "Sample: $SAMPLE_NAME" >> "$SUMMARY_FILE"
echo "BAM: $BAM" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# --- 1. Strandedness (RSeQC infer_experiment.py) ---
if [[ -n "$BED" ]]; then
  echo "--- [1/5] Inferring strandedness ---"
  STRAND_OUT="${RSEQC_DIR}/${SAMPLE_NAME}.infer_experiment.txt"
  infer_experiment.py -i "$BAM" -r "$BED" > "$STRAND_OUT" 2>&1 || true

  if [[ -f "$STRAND_OUT" ]]; then
    echo "Strandedness results:"
    cat "$STRAND_OUT"
    echo "" >> "$SUMMARY_FILE"
    echo "--- Strandedness ---" >> "$SUMMARY_FILE"
    cat "$STRAND_OUT" >> "$SUMMARY_FILE"
  fi
else
  echo "--- [1/5] Skipping strandedness (no BED file provided) ---"
  echo "--- Strandedness: SKIPPED (no BED file) ---" >> "$SUMMARY_FILE"
fi

# --- 2. Gene body coverage (RSeQC geneBody_coverage.py) ---
if [[ -n "$BED" ]]; then
  echo "--- [2/5] Gene body coverage ---"
  GENEBODY_PREFIX="${RSEQC_DIR}/${SAMPLE_NAME}"
  geneBody_coverage.py -i "$BAM" -r "$BED" -o "$GENEBODY_PREFIX" 2>&1 || true

  if [[ -f "${GENEBODY_PREFIX}.geneBodyCoverage.txt" ]]; then
    echo "" >> "$SUMMARY_FILE"
    echo "--- Gene Body Coverage ---" >> "$SUMMARY_FILE"
    echo "Coverage profile written to: ${GENEBODY_PREFIX}.geneBodyCoverage.txt" >> "$SUMMARY_FILE"
    echo "Coverage plot written to: ${GENEBODY_PREFIX}.geneBodyCoverage.curves.pdf" >> "$SUMMARY_FILE"
  fi
else
  echo "--- [2/5] Skipping gene body coverage (no BED file provided) ---"
  echo "--- Gene Body Coverage: SKIPPED (no BED file) ---" >> "$SUMMARY_FILE"
fi

# --- 3. Read distribution (RSeQC read_distribution.py) ---
if [[ -n "$BED" ]]; then
  echo "--- [3/5] Read distribution ---"
  READ_DIST_OUT="${RSEQC_DIR}/${SAMPLE_NAME}.read_distribution.txt"
  read_distribution.py -i "$BAM" -r "$BED" > "$READ_DIST_OUT" 2>&1 || true

  if [[ -f "$READ_DIST_OUT" ]]; then
    echo "Read distribution results:"
    cat "$READ_DIST_OUT"
    echo "" >> "$SUMMARY_FILE"
    echo "--- Read Distribution ---" >> "$SUMMARY_FILE"
    cat "$READ_DIST_OUT" >> "$SUMMARY_FILE"
  fi
else
  echo "--- [3/5] Skipping read distribution (no BED file provided) ---"
  echo "--- Read Distribution: SKIPPED (no BED file) ---" >> "$SUMMARY_FILE"
fi

# --- 4. Inner distance (RSeQC inner_distance.py, paired-end only) ---
# Check if BAM contains paired-end reads
IS_PAIRED=$(samtools view -c -f 1 "$BAM" | head -1)
if [[ "$IS_PAIRED" -gt 0 ]] && [[ -n "$BED" ]]; then
  echo "--- [4/5] Inner distance (paired-end) ---"
  INNER_PREFIX="${RSEQC_DIR}/${SAMPLE_NAME}"
  inner_distance.py -i "$BAM" -r "$BED" -o "$INNER_PREFIX" 2>&1 || true

  echo "" >> "$SUMMARY_FILE"
  echo "--- Inner Distance ---" >> "$SUMMARY_FILE"
  echo "Inner distance plot written to: ${INNER_PREFIX}.inner_distance_plot.pdf" >> "$SUMMARY_FILE"
else
  echo "--- [4/5] Skipping inner distance (single-end or no BED file) ---"
  echo "--- Inner Distance: SKIPPED ---" >> "$SUMMARY_FILE"
fi

# --- 5. Qualimap RNA-seq QC ---
if [[ -n "$GTF" ]]; then
  echo "--- [5/5] Qualimap RNA-seq QC ---"
  mkdir -p "$QUALIMAP_DIR"

  qualimap rnaseq \
    -bam "$BAM" \
    -gtf "$GTF" \
    -outdir "$QUALIMAP_DIR" \
    --java-mem-size=4G \
    2>&1 || true

  # Extract rRNA rate from Qualimap if available
  QUALIMAP_RESULTS="${QUALIMAP_DIR}/rnaseq_qc_results.txt"
  if [[ -f "$QUALIMAP_RESULTS" ]]; then
    echo "" >> "$SUMMARY_FILE"
    echo "--- Qualimap RNA-seq Metrics ---" >> "$SUMMARY_FILE"

    # Extract key metrics
    while IFS= read -r line; do
      case "$line" in
        *"reads aligned"*|*"rRNA"*|*"exonic"*|*"intronic"*|*"intergenic"*|*"5'-3'"*)
          echo "  $line" >> "$SUMMARY_FILE"
          ;;
      esac
    done < "$QUALIMAP_RESULTS"

    echo "Full Qualimap report: ${QUALIMAP_DIR}/qualimapReport.html" >> "$SUMMARY_FILE"
  fi
else
  echo "--- [5/5] Skipping Qualimap (no GTF file provided) ---"
  echo "--- Qualimap: SKIPPED (no GTF file) ---" >> "$SUMMARY_FILE"
fi

# --- Final summary ---
echo ""
echo "========================================="
echo "=== QC Summary ==="
echo "========================================="
cat "$SUMMARY_FILE"
echo ""
echo "=== Alignment QC complete ==="
echo "Output directory: $OUTDIR"
echo "Summary file: $SUMMARY_FILE"
