#!/usr/bin/env bash
set -euo pipefail

# genome-read-alignment/scripts/run.sh
# Align FASTQ reads to a reference genome with BWA-MEM2, sort, index, and mark duplicates.

usage() {
    cat <<EOF
Usage: $(basename "$0") -1 READ1 -r REFERENCE [OPTIONS]

Required:
  -1, --read1         Path to forward FASTQ (R1)
  -r, --ref           Path to reference FASTA (must be BWA-MEM2 indexed)

Optional:
  -2, --read2         Path to reverse FASTQ (R2, for paired-end)
  --outdir            Output directory (default: .)
  --threads           Number of threads (default: 4)
  --rg                Full read group string (e.g., '@RG\tID:samp\tSM:samp\tPL:ILLUMINA\tLB:lib1\tPU:unit1')
  --sample-name       Sample name for auto-generated read group (default: derived from FASTQ filename)
  --tmp-dir           Temporary directory for intermediate files
  -h, --help          Show this help message

EOF
    exit 1
}

# ── Defaults ──────────────────────────────────────────────────────────────────
READ1=""
READ2=""
REFERENCE=""
OUTDIR="."
THREADS=4
RG=""
SAMPLE_NAME=""
TMP_DIR=""

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -1|--read1)      READ1="$2";       shift 2 ;;
        -2|--read2)      READ2="$2";       shift 2 ;;
        -r|--ref)        REFERENCE="$2";   shift 2 ;;
        --outdir)        OUTDIR="$2";      shift 2 ;;
        --threads)       THREADS="$2";     shift 2 ;;
        --rg)            RG="$2";          shift 2 ;;
        --sample-name)   SAMPLE_NAME="$2"; shift 2 ;;
        --tmp-dir)       TMP_DIR="$2";     shift 2 ;;
        -h|--help)       usage ;;
        *)               echo "ERROR: Unknown argument: $1" >&2; usage ;;
    esac
done

# ── Validate required inputs ─────────────────────────────────────────────────
if [[ -z "$READ1" ]]; then
    echo "ERROR: --read1 (-1) is required." >&2
    usage
fi
if [[ -z "$REFERENCE" ]]; then
    echo "ERROR: --ref (-r) is required." >&2
    usage
fi
if [[ ! -f "$READ1" ]]; then
    echo "ERROR: READ1 file not found: $READ1" >&2
    exit 1
fi
if [[ -n "$READ2" && ! -f "$READ2" ]]; then
    echo "ERROR: READ2 file not found: $READ2" >&2
    exit 1
fi
if [[ ! -f "$REFERENCE" ]]; then
    echo "ERROR: Reference FASTA not found: $REFERENCE" >&2
    exit 1
fi

# ── Validate reference index files ───────────────────────────────────────────
MISSING_IDX=0
for ext in .0123 .amb .ann .bwt.2bit.64 .pac; do
    if [[ ! -f "${REFERENCE}${ext}" ]]; then
        echo "WARNING: Missing BWA-MEM2 index file: ${REFERENCE}${ext}" >&2
        MISSING_IDX=1
    fi
done
for ext in .fai; do
    if [[ ! -f "${REFERENCE}${ext}" ]]; then
        echo "WARNING: Missing samtools index file: ${REFERENCE}${ext}" >&2
        MISSING_IDX=1
    fi
done
REF_BASE="${REFERENCE%.*}"
if [[ ! -f "${REF_BASE}.dict" && ! -f "${REFERENCE}.dict" ]]; then
    echo "WARNING: Missing sequence dictionary (.dict) file." >&2
    MISSING_IDX=1
fi
if [[ "$MISSING_IDX" -eq 1 ]]; then
    echo "ERROR: One or more required index files are missing. Please index the reference first." >&2
    exit 1
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"

# Derive sample name from FASTQ filename if not provided
if [[ -z "$SAMPLE_NAME" ]]; then
    SAMPLE_NAME=$(basename "$READ1" | sed -E 's/(_R?[12])?(_001)?\.(fastq|fq)(\.gz)?$//')
fi

SORTED_BAM="${OUTDIR}/${SAMPLE_NAME}.sorted.bam"
DEDUP_BAM="${OUTDIR}/${SAMPLE_NAME}.dedup.bam"
DEDUP_METRICS="${OUTDIR}/${SAMPLE_NAME}.dedup_metrics.txt"

TMP_ARGS=""
if [[ -n "$TMP_DIR" ]]; then
    mkdir -p "$TMP_DIR"
    TMP_ARGS="--TMP_DIR $TMP_DIR"
fi

# ── Construct read group if not provided ──────────────────────────────────────
if [[ -z "$RG" ]]; then
    RG="@RG\tID:${SAMPLE_NAME}\tSM:${SAMPLE_NAME}\tPL:ILLUMINA\tLB:${SAMPLE_NAME}_lib1\tPU:${SAMPLE_NAME}_unit1"
fi

# ── Step 1: Align with BWA-MEM2 and sort ─────────────────────────────────────
echo "=== Aligning reads with BWA-MEM2 and sorting ==="
FASTQ_INPUTS="$READ1"
if [[ -n "$READ2" ]]; then
    FASTQ_INPUTS="$READ1 $READ2"
fi

bwa-mem2 mem \
    -t "$THREADS" \
    -R "$RG" \
    "$REFERENCE" \
    $FASTQ_INPUTS \
  | samtools sort \
    -@ "$THREADS" \
    -o "$SORTED_BAM" \
    -

echo "Sorted BAM: $SORTED_BAM"

# ── Step 2: Index sorted BAM ─────────────────────────────────────────────────
echo "=== Indexing sorted BAM ==="
samtools index -@ "$THREADS" "$SORTED_BAM"
echo "Index: ${SORTED_BAM}.bai"

# ── Step 3: Mark duplicates with picard ───────────────────────────────────────
echo "=== Marking duplicates with picard ==="
picard MarkDuplicates \
    INPUT="$SORTED_BAM" \
    OUTPUT="$DEDUP_BAM" \
    METRICS_FILE="$DEDUP_METRICS" \
    REMOVE_DUPLICATES=false \
    VALIDATION_STRINGENCY=SILENT \
    $TMP_ARGS

echo "Deduplicated BAM: $DEDUP_BAM"
echo "Duplicate metrics: $DEDUP_METRICS"

# ── Step 4: Index deduplicated BAM ────────────────────────────────────────────
echo "=== Indexing deduplicated BAM ==="
samtools index -@ "$THREADS" "$DEDUP_BAM"
echo "Index: ${DEDUP_BAM}.bai"

# ── Step 5: Alignment summary ────────────────────────────────────────────────
echo ""
echo "=== Alignment Summary ==="
samtools flagstat "$DEDUP_BAM" | tee "${OUTDIR}/${SAMPLE_NAME}.flagstat.txt"

echo ""
echo "=== Done ==="
echo "Output files:"
echo "  BAM:             $DEDUP_BAM"
echo "  BAM index:       ${DEDUP_BAM}.bai"
echo "  Dedup metrics:   $DEDUP_METRICS"
echo "  Flagstat:        ${OUTDIR}/${SAMPLE_NAME}.flagstat.txt"
