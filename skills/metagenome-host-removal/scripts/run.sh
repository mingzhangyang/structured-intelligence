#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") -1 READ1 [-2 READ2] --host-index INDEX [OPTIONS]"
    echo ""
    echo "Remove host-derived reads from metagenomic FASTQ files."
    echo ""
    echo "Required:"
    echo "  -1 FILE            Forward reads FASTQ (SE or PE)"
    echo "  --host-index PATH  Path to host genome index prefix"
    echo ""
    echo "Optional:"
    echo "  -2 FILE            Reverse reads FASTQ (PE mode)"
    echo "  --aligner STR      Aligner to use: bowtie2 or bwa-mem2 (default: bowtie2)"
    echo "  --outdir DIR       Output directory (default: host_removal_results)"
    echo "  --threads N        Number of threads (default: 4)"
    echo "  --sensitivity STR  Bowtie2 sensitivity preset (default: --very-sensitive)"
    echo "  -h, --help         Show this help message"
    exit "${1:-0}"
}

READ1=""
READ2=""
HOST_INDEX=""
ALIGNER="bowtie2"
OUTDIR="host_removal_results"
THREADS=4
SENSITIVITY="--very-sensitive"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -1) READ1="$2"; shift 2 ;;
        -2) READ2="$2"; shift 2 ;;
        --host-index) HOST_INDEX="$2"; shift 2 ;;
        --aligner) ALIGNER="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --sensitivity) SENSITIVITY="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) echo "Unexpected argument: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$READ1" ]]; then
    echo "Error: -1 READ1 is required." >&2
    usage 1
fi

if [[ -z "$HOST_INDEX" ]]; then
    echo "Error: --host-index is required." >&2
    usage 1
fi

if [[ "$ALIGNER" != "bowtie2" && "$ALIGNER" != "bwa-mem2" ]]; then
    echo "Error: --aligner must be 'bowtie2' or 'bwa-mem2'." >&2
    exit 1
fi

mkdir -p "$OUTDIR"

SAMPLE=$(basename "$READ1" | sed -E 's/(_R1)?(_001)?\.(fastq|fq)(\.gz)?$//')
BAM="$OUTDIR/${SAMPLE}_host_aligned.bam"
UNMAPPED_BAM="$OUTDIR/${SAMPLE}_unmapped.bam"
SORTED_BAM="$OUTDIR/${SAMPLE}_unmapped_sorted.bam"

PE_MODE=false
if [[ -n "$READ2" ]]; then
    PE_MODE=true
fi

# Step 1: Align reads to host reference genome
echo "==> Aligning reads to host genome with $ALIGNER..."
if [[ "$ALIGNER" == "bowtie2" ]]; then
    if $PE_MODE; then
        bowtie2 "$SENSITIVITY" -p "$THREADS" -x "$HOST_INDEX" \
            -1 "$READ1" -2 "$READ2" 2>"$OUTDIR/${SAMPLE}_bowtie2.log" \
            | samtools view -@ "$THREADS" -bS - > "$BAM"
    else
        bowtie2 "$SENSITIVITY" -p "$THREADS" -x "$HOST_INDEX" \
            -U "$READ1" 2>"$OUTDIR/${SAMPLE}_bowtie2.log" \
            | samtools view -@ "$THREADS" -bS - > "$BAM"
    fi
elif [[ "$ALIGNER" == "bwa-mem2" ]]; then
    if $PE_MODE; then
        bwa-mem2 mem -t "$THREADS" "$HOST_INDEX" "$READ1" "$READ2" \
            2>"$OUTDIR/${SAMPLE}_bwa-mem2.log" \
            | samtools view -@ "$THREADS" -bS - > "$BAM"
    else
        bwa-mem2 mem -t "$THREADS" "$HOST_INDEX" "$READ1" \
            2>"$OUTDIR/${SAMPLE}_bwa-mem2.log" \
            | samtools view -@ "$THREADS" -bS - > "$BAM"
    fi
fi

# Step 2: Extract unmapped reads
echo "==> Extracting unmapped reads..."
if $PE_MODE; then
    # -f 12: both reads in pair unmapped
    samtools view -@ "$THREADS" -b -f 12 "$BAM" > "$UNMAPPED_BAM"
else
    # -f 4: read unmapped
    samtools view -@ "$THREADS" -b -f 4 "$BAM" > "$UNMAPPED_BAM"
fi

# Step 3: Sort unmapped reads by name
echo "==> Sorting unmapped reads by name..."
samtools sort -@ "$THREADS" -n "$UNMAPPED_BAM" -o "$SORTED_BAM"

# Step 4: Convert back to FASTQ
echo "==> Converting to FASTQ..."
if $PE_MODE; then
    samtools fastq -@ "$THREADS" \
        -1 "$OUTDIR/${SAMPLE}_hostdepleted_R1.fastq.gz" \
        -2 "$OUTDIR/${SAMPLE}_hostdepleted_R2.fastq.gz" \
        -0 /dev/null -s /dev/null \
        "$SORTED_BAM"
else
    samtools fastq -@ "$THREADS" \
        "$SORTED_BAM" | gzip > "$OUTDIR/${SAMPLE}_hostdepleted.fastq.gz"
fi

# Step 5: Calculate statistics
echo "==> Computing host removal statistics..."
TOTAL_READS=$(samtools view -@ "$THREADS" -c "$BAM")
UNMAPPED_READS=$(samtools view -@ "$THREADS" -c "$UNMAPPED_BAM")
HOST_READS=$((TOTAL_READS - UNMAPPED_READS))

if [[ "$TOTAL_READS" -gt 0 ]]; then
    HOST_PCT=$(awk "BEGIN {printf \"%.2f\", ($HOST_READS / $TOTAL_READS) * 100}")
else
    HOST_PCT="0.00"
fi

SUMMARY="$OUTDIR/${SAMPLE}_host_removal_summary.txt"
cat > "$SUMMARY" <<EOF
Host Removal Summary
====================
Sample:             $SAMPLE
Aligner:            $ALIGNER
Total reads:        $TOTAL_READS
Host reads removed: $HOST_READS
Non-host retained:  $UNMAPPED_READS
Host contamination: ${HOST_PCT}%
EOF

echo "==> Host removal complete."
cat "$SUMMARY"

# Clean up intermediate BAM files
rm -f "$BAM" "$UNMAPPED_BAM" "$SORTED_BAM"

echo "==> Output files:"
if $PE_MODE; then
    echo "  $OUTDIR/${SAMPLE}_hostdepleted_R1.fastq.gz"
    echo "  $OUTDIR/${SAMPLE}_hostdepleted_R2.fastq.gz"
else
    echo "  $OUTDIR/${SAMPLE}_hostdepleted.fastq.gz"
fi
echo "  $SUMMARY"
