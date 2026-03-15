#!/usr/bin/env bash
set -euo pipefail

# rnaseq-transcript-quantification: Alignment-free transcript quantification using Salmon or kallisto

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required:
  -1, --read1 FILE        Forward (or single-end) FASTQ file
  --index DIR/FILE        Transcriptome index directory (Salmon) or file (kallisto)

Optional:
  -2, --read2 FILE        Reverse FASTQ file (paired-end)
  --tool STR              Quantification tool: salmon or kallisto (default: salmon)
  --libtype STR           Library type for Salmon (default: A for auto-detect)
  --outdir DIR            Output directory (default: ./quant_output)
  --threads INT           Number of threads (default: 4)
  --bootstraps INT        Number of bootstrap samples (default: 0, disabled)
  -h, --help              Show this help message
EOF
  exit 1
}

# Defaults
READ1=""
READ2=""
INDEX=""
TOOL="salmon"
LIBTYPE="A"
OUTDIR="./quant_output"
THREADS=4
BOOTSTRAPS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -1|--read1)      READ1="$2"; shift 2 ;;
    -2|--read2)      READ2="$2"; shift 2 ;;
    --index)         INDEX="$2"; shift 2 ;;
    --tool)          TOOL="$2"; shift 2 ;;
    --libtype)       LIBTYPE="$2"; shift 2 ;;
    --outdir)        OUTDIR="$2"; shift 2 ;;
    --threads)       THREADS="$2"; shift 2 ;;
    --bootstraps)    BOOTSTRAPS="$2"; shift 2 ;;
    -h|--help)       usage ;;
    *)               echo "Error: unknown option $1" >&2; usage ;;
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

echo "=== RNA-seq Transcript Quantification ==="
echo "Tool:        $TOOL"
echo "Read1:       $READ1"
echo "Read2:       ${READ2:-none (single-end)}"
echo "Index:       $INDEX"
echo "Output:      $OUTDIR"
echo "Threads:     $THREADS"
echo "Bootstraps:  $BOOTSTRAPS"

if [[ "$TOOL" == "salmon" ]]; then
  # Validate Salmon index
  if [[ ! -d "$INDEX" ]]; then
    echo "Error: Salmon index directory not found at $INDEX" >&2
    exit 1
  fi

  # Build Salmon command
  SALMON_CMD=(salmon quant
    -i "$INDEX"
    -l "$LIBTYPE"
    -o "$OUTDIR"
    -p "$THREADS"
    --validateMappings
    --seqBias
    --gcBias
  )

  # Paired-end or single-end
  if [[ -n "$READ2" ]]; then
    SALMON_CMD+=(-1 "$READ1" -2 "$READ2")
  else
    SALMON_CMD+=(-r "$READ1")
  fi

  # Bootstraps
  if [[ "$BOOTSTRAPS" -gt 0 ]]; then
    SALMON_CMD+=(--numBootstraps "$BOOTSTRAPS")
  fi

  echo "--- Running Salmon quantification ---"
  "${SALMON_CMD[@]}"

  # Report summary
  echo ""
  echo "=== Quantification Summary ==="
  if [[ -f "${OUTDIR}/aux_info/meta_info.json" ]]; then
    echo "Mapping rate and read counts:"
    python3 -c "
import json
with open('${OUTDIR}/aux_info/meta_info.json') as f:
    info = json.load(f)
print(f\"  Total reads processed: {info.get('num_processed', 'N/A')}\")
print(f\"  Mapping rate: {info.get('percent_mapped', 'N/A')}%\")
print(f\"  Quantified transcripts: {info.get('num_quantified_transcripts', 'N/A')}\")
" 2>/dev/null || echo "  (Install python3 to parse Salmon meta_info.json)"
  fi

elif [[ "$TOOL" == "kallisto" ]]; then
  # Validate kallisto index
  if [[ ! -f "$INDEX" ]]; then
    echo "Error: kallisto index file not found at $INDEX" >&2
    exit 1
  fi

  # Build kallisto command
  KALLISTO_CMD=(kallisto quant
    -i "$INDEX"
    -o "$OUTDIR"
    -t "$THREADS"
  )

  # Bootstraps
  if [[ "$BOOTSTRAPS" -gt 0 ]]; then
    KALLISTO_CMD+=(-b "$BOOTSTRAPS")
  fi

  # Paired-end or single-end
  if [[ -n "$READ2" ]]; then
    KALLISTO_CMD+=("$READ1" "$READ2")
  else
    # Single-end requires --single plus fragment length info
    KALLISTO_CMD+=(--single -l 200 -s 20 "$READ1")
    echo "Warning: single-end mode using default fragment length 200 +/- 20. Adjust if needed."
  fi

  echo "--- Running kallisto quantification ---"
  "${KALLISTO_CMD[@]}"

  # Report summary
  echo ""
  echo "=== Quantification Summary ==="
  if [[ -f "${OUTDIR}/run_info.json" ]]; then
    python3 -c "
import json
with open('${OUTDIR}/run_info.json') as f:
    info = json.load(f)
print(f\"  Total reads processed: {info.get('n_processed', 'N/A')}\")
print(f\"  Pseudoaligned: {info.get('n_pseudoaligned', 'N/A')}\")
print(f\"  Unique transcripts quantified: {info.get('n_unique', 'N/A')}\")
p_rate = info.get('p_pseudoaligned', 'N/A')
print(f\"  Pseudoalignment rate: {p_rate}%\")
" 2>/dev/null || echo "  (Install python3 to parse kallisto run_info.json)"
  fi

else
  echo "Error: unknown tool '$TOOL'. Choose 'salmon' or 'kallisto'." >&2
  exit 1
fi

echo ""
echo "=== Quantification complete ==="
echo "Output directory: $OUTDIR"
