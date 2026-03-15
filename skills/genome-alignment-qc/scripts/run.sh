#!/usr/bin/env bash
set -euo pipefail

# genome-alignment-qc/scripts/run.sh
# Assess alignment quality with coverage, mapping rates, insert size, and on-target metrics.

usage() {
    cat <<EOF
Usage: $(basename "$0") --bam BAM [OPTIONS]

Required:
  --bam               BAM file with index

Optional:
  --ref               Reference FASTA (required for picard metrics)
  --bed               Target BED file (for WES on-target metrics)
  --outdir            Output directory (default: .)
  --threads           Number of threads (default: 4)
  --per-base          Enable mosdepth per-base coverage output (flag)
  -h, --help          Show this help message

EOF
    exit 1
}

# ── Defaults ──────────────────────────────────────────────────────────────────
BAM=""
REFERENCE=""
BED=""
OUTDIR="."
THREADS=4
PER_BASE=false

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bam)       BAM="$2";       shift 2 ;;
        --ref)       REFERENCE="$2"; shift 2 ;;
        --bed)       BED="$2";       shift 2 ;;
        --outdir)    OUTDIR="$2";    shift 2 ;;
        --threads)   THREADS="$2";   shift 2 ;;
        --per-base)  PER_BASE=true;  shift 1 ;;
        -h|--help)   usage ;;
        *)           echo "ERROR: Unknown argument: $1" >&2; usage ;;
    esac
done

# ── Validate required inputs ─────────────────────────────────────────────────
if [[ -z "$BAM" ]]; then
    echo "ERROR: --bam is required." >&2; usage
fi
if [[ ! -f "$BAM" ]]; then
    echo "ERROR: BAM file not found: $BAM" >&2; exit 1
fi
if [[ ! -f "${BAM}.bai" && ! -f "${BAM%.*}.bai" ]]; then
    echo "ERROR: BAM index not found for: $BAM" >&2; exit 1
fi
if [[ -n "$BED" && ! -f "$BED" ]]; then
    echo "ERROR: BED file not found: $BED" >&2; exit 1
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"

SAMPLE_NAME=$(basename "$BAM" .bam)
PREFIX="${OUTDIR}/${SAMPLE_NAME}"

# ── Step 1: samtools flagstat ─────────────────────────────────────────────────
echo "=== Running samtools flagstat ==="
samtools flagstat -@ "$THREADS" "$BAM" > "${PREFIX}.flagstat.txt"
echo "Output: ${PREFIX}.flagstat.txt"

# ── Step 2: samtools stats ───────────────────────────────────────────────────
echo "=== Running samtools stats ==="
samtools stats -@ "$THREADS" "$BAM" > "${PREFIX}.samtools_stats.txt"
echo "Output: ${PREFIX}.samtools_stats.txt"

# ── Step 3: samtools idxstats ────────────────────────────────────────────────
echo "=== Running samtools idxstats ==="
samtools idxstats "$BAM" > "${PREFIX}.idxstats.txt"
echo "Output: ${PREFIX}.idxstats.txt"

# ── Step 4: mosdepth coverage ────────────────────────────────────────────────
echo "=== Running mosdepth ==="

MOSDEPTH_ARGS=(
    mosdepth
    --threads "$THREADS"
)

if [[ "$PER_BASE" == false ]]; then
    MOSDEPTH_ARGS+=(--no-per-base)
fi

if [[ -n "$BED" ]]; then
    MOSDEPTH_ARGS+=(--by "$BED")
fi

MOSDEPTH_ARGS+=("$PREFIX" "$BAM")

"${MOSDEPTH_ARGS[@]}"
echo "Coverage outputs: ${PREFIX}.mosdepth.global.dist.txt"

# ── Step 5: On-target rate (if BED provided) ─────────────────────────────────
ON_TARGET_RATE=""
if [[ -n "$BED" ]]; then
    echo "=== Computing on-target rate ==="

    TOTAL_READS=$(samtools view -c -F 4 -@ "$THREADS" "$BAM")
    ON_TARGET_READS=$(samtools view -c -F 4 -@ "$THREADS" -L "$BED" "$BAM")

    if [[ "$TOTAL_READS" -gt 0 ]]; then
        ON_TARGET_RATE=$(awk "BEGIN {printf \"%.2f\", ($ON_TARGET_READS / $TOTAL_READS) * 100}")
    else
        ON_TARGET_RATE="0.00"
    fi

    echo "Mapped reads:    $TOTAL_READS"
    echo "On-target reads: $ON_TARGET_READS"
    echo "On-target rate:  ${ON_TARGET_RATE}%"
fi

# ── Step 6: picard CollectInsertSizeMetrics ───────────────────────────────────
if [[ -n "$REFERENCE" ]]; then
    echo "=== Running picard CollectInsertSizeMetrics ==="
    picard CollectInsertSizeMetrics \
        INPUT="$BAM" \
        OUTPUT="${PREFIX}.insert_size_metrics.txt" \
        HISTOGRAM_FILE="${PREFIX}.insert_size_histogram.pdf" \
        VALIDATION_STRINGENCY=SILENT
    echo "Output: ${PREFIX}.insert_size_metrics.txt"

    # ── Step 7: picard CollectAlignmentSummaryMetrics ─────────────────────────
    echo "=== Running picard CollectAlignmentSummaryMetrics ==="
    picard CollectAlignmentSummaryMetrics \
        INPUT="$BAM" \
        OUTPUT="${PREFIX}.alignment_summary_metrics.txt" \
        REFERENCE_SEQUENCE="$REFERENCE" \
        VALIDATION_STRINGENCY=SILENT
    echo "Output: ${PREFIX}.alignment_summary_metrics.txt"
else
    echo "NOTICE: --ref not provided; skipping picard metrics (CollectInsertSizeMetrics, CollectAlignmentSummaryMetrics)."
fi

# ── Step 8: Compile QC summary ────────────────────────────────────────────────
echo ""
echo "=== Compiled QC Summary ==="
SUMMARY_FILE="${PREFIX}.qc_summary.txt"

{
    echo "Sample: $SAMPLE_NAME"
    echo ""

    # Mapping rate from flagstat
    echo "--- Mapping Statistics ---"
    TOTAL_READS=$(grep "in total" "${PREFIX}.flagstat.txt" | awk '{print $1}')
    MAPPED_READS=$(grep "mapped (" "${PREFIX}.flagstat.txt" | head -1 | awk '{print $1}')
    PAIRED_READS=$(grep "properly paired" "${PREFIX}.flagstat.txt" | awk '{print $1}')
    DUP_READS=$(grep "duplicates" "${PREFIX}.flagstat.txt" | awk '{print $1}')

    echo "Total reads:        $TOTAL_READS"
    echo "Mapped reads:       $MAPPED_READS"
    echo "Properly paired:    $PAIRED_READS"
    echo "Duplicates:         $DUP_READS"

    if [[ "$TOTAL_READS" -gt 0 ]]; then
        MAP_RATE=$(awk "BEGIN {printf \"%.2f\", ($MAPPED_READS / $TOTAL_READS) * 100}")
        DUP_RATE=$(awk "BEGIN {printf \"%.2f\", ($DUP_READS / $TOTAL_READS) * 100}")
        echo "Mapping rate:       ${MAP_RATE}%"
        echo "Duplicate rate:     ${DUP_RATE}%"
    fi

    echo ""

    # Mean coverage from mosdepth summary
    echo "--- Coverage ---"
    if [[ -f "${PREFIX}.mosdepth.summary.txt" ]]; then
        MEAN_COV=$(grep "total" "${PREFIX}.mosdepth.summary.txt" | tail -1 | awk '{print $4}')
        echo "Mean coverage:      ${MEAN_COV}x"
    fi

    # On-target rate if WES
    if [[ -n "$BED" ]]; then
        echo "On-target rate:     ${ON_TARGET_RATE}%"
    fi

    echo ""

    # Insert size from picard
    if [[ -f "${PREFIX}.insert_size_metrics.txt" ]]; then
        echo "--- Insert Size ---"
        MEDIAN_INSERT=$(grep -A1 "^MEDIAN_INSERT_SIZE" "${PREFIX}.insert_size_metrics.txt" | tail -1 | cut -f1)
        echo "Median insert size: $MEDIAN_INSERT"
    fi

} | tee "$SUMMARY_FILE"

echo ""
echo "=== Done ==="
echo "Output files:"
echo "  Flagstat:            ${PREFIX}.flagstat.txt"
echo "  Samtools stats:      ${PREFIX}.samtools_stats.txt"
echo "  Idxstats:            ${PREFIX}.idxstats.txt"
echo "  Mosdepth coverage:   ${PREFIX}.mosdepth.global.dist.txt"
if [[ -n "$REFERENCE" ]]; then
    echo "  Insert size metrics: ${PREFIX}.insert_size_metrics.txt"
    echo "  Alignment summary:   ${PREFIX}.alignment_summary_metrics.txt"
fi
echo "  QC summary:          $SUMMARY_FILE"
