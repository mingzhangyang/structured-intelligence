#!/usr/bin/env bash
set -euo pipefail

# rnaseq-read-alignment: Splice-aware alignment of RNA-seq reads using STAR or HISAT2

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required:
  -1, --read1 FILE        Forward (or single-end) FASTQ file
  --index DIR/PREFIX      Genome index directory (STAR) or prefix (HISAT2)

Optional:
  -2, --read2 FILE        Reverse FASTQ file (paired-end)
  --aligner STR           Aligner to use: star or hisat2 (default: star)
  --gtf FILE              GTF annotation file
  --outdir DIR            Output directory (default: ./alignment_output)
  --threads INT           Number of threads (default: 4)
  --two-pass              Enable STAR two-pass mode for novel junction discovery
  --max-intron INT        Maximum intron length
  -h, --help              Show this help message
EOF
  exit 1
}

# Defaults
READ1=""
READ2=""
INDEX=""
ALIGNER="star"
GTF=""
OUTDIR="./alignment_output"
THREADS=4
TWO_PASS=false
MAX_INTRON=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -1|--read1)   READ1="$2"; shift 2 ;;
    -2|--read2)   READ2="$2"; shift 2 ;;
    --index)      INDEX="$2"; shift 2 ;;
    --aligner)    ALIGNER="$2"; shift 2 ;;
    --gtf)        GTF="$2"; shift 2 ;;
    --outdir)     OUTDIR="$2"; shift 2 ;;
    --threads)    THREADS="$2"; shift 2 ;;
    --two-pass)   TWO_PASS=true; shift ;;
    --max-intron) MAX_INTRON="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *)            echo "Error: unknown option $1" >&2; usage ;;
  esac
done

# Validate required arguments
if [[ -z "$READ1" ]]; then
  echo "Error: --read1 is required." >&2
  usage
fi
if [[ -z "$INDEX" ]]; then
  echo "Error: --index is required." >&2
  usage
fi

mkdir -p "$OUTDIR"

echo "=== RNA-seq Read Alignment ==="
echo "Aligner: $ALIGNER"
echo "Read1:   $READ1"
echo "Read2:   ${READ2:-none (single-end)}"
echo "Index:   $INDEX"
echo "Output:  $OUTDIR"
echo "Threads: $THREADS"

if [[ "$ALIGNER" == "star" ]]; then
  # Validate STAR genome index
  if [[ ! -d "$INDEX" ]] || [[ ! -f "$INDEX/SA" ]]; then
    echo "Error: STAR genome index not found at $INDEX" >&2
    exit 1
  fi

  # Build STAR command
  STAR_CMD=(STAR
    --runThreadN "$THREADS"
    --genomeDir "$INDEX"
    --readFilesIn "$READ1"
    --outSAMtype BAM SortedByCoordinate
    --quantMode GeneCounts
    --outFileNamePrefix "${OUTDIR}/"
  )

  # Add read2 for paired-end
  if [[ -n "$READ2" ]]; then
    STAR_CMD+=(--readFilesIn "$READ1" "$READ2")
  fi

  # Handle compressed input
  if [[ "$READ1" == *.gz ]]; then
    STAR_CMD+=(--readFilesCommand zcat)
  fi

  # GTF annotation
  if [[ -n "$GTF" ]]; then
    STAR_CMD+=(--sjdbGTFfile "$GTF")
  fi

  # Max intron length
  if [[ -n "$MAX_INTRON" ]]; then
    STAR_CMD+=(--alignIntronMax "$MAX_INTRON")
  fi

  if [[ "$TWO_PASS" == true ]]; then
    echo "--- STAR two-pass mode: first pass ---"
    PASS1_DIR="${OUTDIR}/star_pass1"
    mkdir -p "$PASS1_DIR"

    PASS1_CMD=("${STAR_CMD[@]}")
    PASS1_CMD+=(--outFileNamePrefix "${PASS1_DIR}/")

    "${PASS1_CMD[@]}"

    echo "--- STAR two-pass mode: generating junction-aware index ---"
    PASS2_GENOME="${OUTDIR}/star_pass2_genome"
    mkdir -p "$PASS2_GENOME"

    STAR --runMode genomeGenerate \
      --runThreadN "$THREADS" \
      --genomeDir "$PASS2_GENOME" \
      --genomeFastaFiles "${INDEX}/../genome.fa" \
      --sjdbFileChrStartEnd "${PASS1_DIR}/SJ.out.tab" \
      --sjdbOverhang 100 \
      ${GTF:+--sjdbGTFfile "$GTF"}

    echo "--- STAR two-pass mode: second pass ---"
    STAR_CMD=(STAR
      --runThreadN "$THREADS"
      --genomeDir "$PASS2_GENOME"
      --readFilesIn "$READ1" ${READ2:+"$READ2"}
      --outSAMtype BAM SortedByCoordinate
      --quantMode GeneCounts
      --outFileNamePrefix "${OUTDIR}/"
    )
    if [[ "$READ1" == *.gz ]]; then
      STAR_CMD+=(--readFilesCommand zcat)
    fi
    if [[ -n "$MAX_INTRON" ]]; then
      STAR_CMD+=(--alignIntronMax "$MAX_INTRON")
    fi

    "${STAR_CMD[@]}"
  else
    echo "--- Running STAR single-pass alignment ---"
    "${STAR_CMD[@]}"
  fi

  # Index the BAM
  echo "--- Indexing BAM ---"
  samtools index "${OUTDIR}/Aligned.sortedByCoord.out.bam"

  # Report summary
  echo ""
  echo "=== Alignment Summary ==="
  if [[ -f "${OUTDIR}/Log.final.out" ]]; then
    cat "${OUTDIR}/Log.final.out"
  fi

elif [[ "$ALIGNER" == "hisat2" ]]; then
  # Validate HISAT2 index
  if ! ls "${INDEX}".*.ht2 &>/dev/null && ! ls "${INDEX}".*.ht2l &>/dev/null; then
    echo "Error: HISAT2 index not found with prefix $INDEX" >&2
    exit 1
  fi

  # Build HISAT2 command
  HISAT2_CMD=(hisat2
    -p "$THREADS"
    -x "$INDEX"
    --dta
    --summary-file "${OUTDIR}/hisat2_summary.txt"
  )

  if [[ -n "$READ2" ]]; then
    HISAT2_CMD+=(-1 "$READ1" -2 "$READ2")
  else
    HISAT2_CMD+=(-U "$READ1")
  fi

  if [[ -n "$MAX_INTRON" ]]; then
    HISAT2_CMD+=(--max-intronlen "$MAX_INTRON")
  fi

  echo "--- Running HISAT2 alignment ---"
  "${HISAT2_CMD[@]}" | samtools sort -@ "$THREADS" -o "${OUTDIR}/aligned.sorted.bam"

  # Index the BAM
  echo "--- Indexing BAM ---"
  samtools index "${OUTDIR}/aligned.sorted.bam"

  # Report summary
  echo ""
  echo "=== Alignment Summary ==="
  if [[ -f "${OUTDIR}/hisat2_summary.txt" ]]; then
    cat "${OUTDIR}/hisat2_summary.txt"
  fi

else
  echo "Error: unknown aligner '$ALIGNER'. Choose 'star' or 'hisat2'." >&2
  exit 1
fi

echo ""
echo "=== Alignment complete ==="
echo "Output directory: $OUTDIR"
