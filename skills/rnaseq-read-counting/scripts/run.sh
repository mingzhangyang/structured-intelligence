#!/usr/bin/env bash
set -euo pipefail

# rnaseq-read-counting: Gene-level read counting from aligned BAMs using featureCounts or HTSeq-count

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required:
  --bam FILE [FILE ...]   One or more coordinate-sorted BAM files
  --gtf FILE              GTF annotation file

Optional:
  --tool STR              Counting tool: featurecounts or htseq (default: featurecounts)
  --strand INT            Strandedness: 0=unstranded, 1=stranded, 2=reverse-stranded (default: 0)
  --outdir DIR            Output directory (default: ./count_output)
  --threads INT           Number of threads (default: 4, featureCounts only)
  --paired                Treat as paired-end reads
  --feature-type STR      Feature type to count (default: exon)
  --attribute STR         Attribute for grouping (default: gene_id)
  --min-quality INT       Minimum mapping quality (default: 10)
  -h, --help              Show this help message
EOF
  exit 1
}

# Defaults
BAM_FILES=()
GTF=""
TOOL="featurecounts"
STRAND=0
OUTDIR="./count_output"
THREADS=4
PAIRED=false
FEATURE_TYPE="exon"
ATTRIBUTE="gene_id"
MIN_QUALITY=10

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bam)
      shift
      while [[ $# -gt 0 ]] && [[ ! "$1" == --* ]]; do
        BAM_FILES+=("$1")
        shift
      done
      ;;
    --gtf)          GTF="$2"; shift 2 ;;
    --tool)         TOOL="$2"; shift 2 ;;
    --strand)       STRAND="$2"; shift 2 ;;
    --outdir)       OUTDIR="$2"; shift 2 ;;
    --threads)      THREADS="$2"; shift 2 ;;
    --paired)       PAIRED=true; shift ;;
    --feature-type) FEATURE_TYPE="$2"; shift 2 ;;
    --attribute)    ATTRIBUTE="$2"; shift 2 ;;
    --min-quality)  MIN_QUALITY="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)              echo "Error: unknown option $1" >&2; usage ;;
  esac
done

# Validate required arguments
if [[ ${#BAM_FILES[@]} -eq 0 ]]; then
  echo "Error: --bam is required (one or more BAM files)." >&2
  usage
fi
if [[ -z "$GTF" ]]; then
  echo "Error: --gtf is required." >&2
  usage
fi

mkdir -p "$OUTDIR"

echo "=== RNA-seq Read Counting ==="
echo "Tool:        $TOOL"
echo "BAM files:   ${BAM_FILES[*]}"
echo "GTF:         $GTF"
echo "Strand:      $STRAND"
echo "Output:      $OUTDIR"
echo "Threads:     $THREADS"
echo "Paired-end:  $PAIRED"

# Validate BAM files exist and are indexed
for bam in "${BAM_FILES[@]}"; do
  if [[ ! -f "$bam" ]]; then
    echo "Error: BAM file not found: $bam" >&2
    exit 1
  fi
  if [[ ! -f "${bam}.bai" ]] && [[ ! -f "${bam%.bam}.bai" ]]; then
    echo "Warning: BAM index not found for $bam. Attempting to create index..."
    samtools index "$bam"
  fi
done

if [[ "$TOOL" == "featurecounts" ]]; then
  OUTPUT_FILE="${OUTDIR}/counts.txt"

  # Build featureCounts command
  FC_CMD=(featureCounts
    -a "$GTF"
    -o "$OUTPUT_FILE"
    -T "$THREADS"
    -s "$STRAND"
    -t "$FEATURE_TYPE"
    -g "$ATTRIBUTE"
    -Q "$MIN_QUALITY"
  )

  # Paired-end flag
  if [[ "$PAIRED" == true ]]; then
    FC_CMD+=(-p --countReadPairs)
  fi

  # Add all BAM files
  FC_CMD+=("${BAM_FILES[@]}")

  echo "--- Running featureCounts ---"
  "${FC_CMD[@]}"

  # Report summary
  echo ""
  echo "=== Counting Summary ==="
  if [[ -f "${OUTPUT_FILE}.summary" ]]; then
    cat "${OUTPUT_FILE}.summary"
  fi

  # Clean column headers to sample names
  echo ""
  echo "Count matrix written to: $OUTPUT_FILE"

elif [[ "$TOOL" == "htseq" ]]; then
  # Map strandedness to HTSeq format
  case "$STRAND" in
    0) HTSEQ_STRAND="no" ;;
    1) HTSEQ_STRAND="yes" ;;
    2) HTSEQ_STRAND="reverse" ;;
    *) echo "Error: invalid strand value '$STRAND'" >&2; exit 1 ;;
  esac

  SAMPLE_FILES=()

  echo "--- Running HTSeq-count ---"
  for bam in "${BAM_FILES[@]}"; do
    SAMPLE_NAME=$(basename "$bam" .bam)
    SAMPLE_OUT="${OUTDIR}/${SAMPLE_NAME}.htseq.txt"

    HTSEQ_CMD=(htseq-count
      --format bam
      --order pos
      --stranded "$HTSEQ_STRAND"
      --type "$FEATURE_TYPE"
      --idattr "$ATTRIBUTE"
      --minaqual "$MIN_QUALITY"
    )

    echo "  Counting: $SAMPLE_NAME"
    "${HTSEQ_CMD[@]}" "$bam" "$GTF" > "$SAMPLE_OUT"
    SAMPLE_FILES+=("$SAMPLE_OUT")
  done

  # Merge per-sample counts into a matrix
  if [[ ${#SAMPLE_FILES[@]} -gt 1 ]]; then
    echo "--- Merging per-sample counts into matrix ---"
    MERGED="${OUTDIR}/counts.txt"

    # Build header
    HEADER="gene_id"
    for bam in "${BAM_FILES[@]}"; do
      HEADER="${HEADER}\t$(basename "$bam" .bam)"
    done
    echo -e "$HEADER" > "$MERGED"

    # Use paste to merge, then filter out HTSeq summary lines
    paste "${SAMPLE_FILES[@]}" \
      | awk -F'\t' 'BEGIN{OFS="\t"} !/^__/ {printf $1; for(i=2;i<=NF;i+=2) printf "\t"$i; printf "\n"}' \
      >> "$MERGED"

    echo "Merged count matrix written to: $MERGED"
  else
    echo "Single-sample count file written to: ${SAMPLE_FILES[0]}"
  fi

  # Report summary (HTSeq summary lines start with __)
  echo ""
  echo "=== Counting Summary ==="
  for sf in "${SAMPLE_FILES[@]}"; do
    echo "--- $(basename "$sf") ---"
    grep "^__" "$sf" || true
  done

else
  echo "Error: unknown tool '$TOOL'. Choose 'featurecounts' or 'htseq'." >&2
  exit 1
fi

echo ""
echo "=== Read counting complete ==="
echo "Output directory: $OUTDIR"
