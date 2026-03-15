#!/usr/bin/env bash
set -euo pipefail

# genome-variant-calling/scripts/run.sh
# Call germline SNVs and indels from an aligned BAM using GATK HaplotypeCaller or DeepVariant.

usage() {
    cat <<EOF
Usage: $(basename "$0") --bam BAM --ref REFERENCE [OPTIONS]

Required:
  --bam               Deduplicated, sorted BAM file with index
  --ref               Reference FASTA with .fai and .dict

Optional:
  --caller            Variant caller: gatk or deepvariant (default: gatk)
  --intervals         Intervals file or BED for target regions (WES)
  --gvcf              Enable GVCF mode for joint genotyping (flag)
  --outdir            Output directory (default: .)
  --threads           Number of threads (default: 4)
  --memory            Java heap memory for GATK (default: 4g)
  --model-type        DeepVariant model type: WGS or WES (default: WGS)
  -h, --help          Show this help message

EOF
    exit 1
}

# ── Defaults ──────────────────────────────────────────────────────────────────
BAM=""
REFERENCE=""
CALLER="gatk"
INTERVALS=""
GVCF=false
OUTDIR="."
THREADS=4
MEMORY="4g"
MODEL_TYPE="WGS"

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bam)          BAM="$2";          shift 2 ;;
        --ref)          REFERENCE="$2";    shift 2 ;;
        --caller)       CALLER="$2";       shift 2 ;;
        --intervals)    INTERVALS="$2";    shift 2 ;;
        --gvcf)         GVCF=true;         shift 1 ;;
        --outdir)       OUTDIR="$2";       shift 2 ;;
        --threads)      THREADS="$2";      shift 2 ;;
        --memory)       MEMORY="$2";       shift 2 ;;
        --model-type)   MODEL_TYPE="$2";   shift 2 ;;
        -h|--help)      usage ;;
        *)              echo "ERROR: Unknown argument: $1" >&2; usage ;;
    esac
done

# ── Validate required inputs ─────────────────────────────────────────────────
if [[ -z "$BAM" ]]; then
    echo "ERROR: --bam is required." >&2; usage
fi
if [[ -z "$REFERENCE" ]]; then
    echo "ERROR: --ref is required." >&2; usage
fi
if [[ ! -f "$BAM" ]]; then
    echo "ERROR: BAM file not found: $BAM" >&2; exit 1
fi
if [[ ! -f "${BAM}.bai" && ! -f "${BAM%.*}.bai" ]]; then
    echo "ERROR: BAM index not found for: $BAM" >&2; exit 1
fi
if [[ ! -f "$REFERENCE" ]]; then
    echo "ERROR: Reference FASTA not found: $REFERENCE" >&2; exit 1
fi
if [[ ! -f "${REFERENCE}.fai" ]]; then
    echo "ERROR: Reference .fai index not found: ${REFERENCE}.fai" >&2; exit 1
fi

# Validate caller choice
CALLER=$(echo "$CALLER" | tr '[:upper:]' '[:lower:]')
if [[ "$CALLER" != "gatk" && "$CALLER" != "deepvariant" ]]; then
    echo "ERROR: --caller must be 'gatk' or 'deepvariant', got: $CALLER" >&2; exit 1
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"

SAMPLE_NAME=$(samtools view -H "$BAM" | grep '^@RG' | head -1 | sed -E 's/.*SM:([^\t]+).*/\1/')
if [[ -z "$SAMPLE_NAME" ]]; then
    SAMPLE_NAME=$(basename "$BAM" .bam)
fi

if [[ "$GVCF" == true ]]; then
    OUTPUT_VCF="${OUTDIR}/${SAMPLE_NAME}.g.vcf.gz"
else
    OUTPUT_VCF="${OUTDIR}/${SAMPLE_NAME}.vcf.gz"
fi

# ── GATK HaplotypeCaller path ────────────────────────────────────────────────
if [[ "$CALLER" == "gatk" ]]; then
    echo "=== Running GATK HaplotypeCaller ==="

    HC_ARGS=(
        gatk --java-options "-Xmx${MEMORY}"
        HaplotypeCaller
        -R "$REFERENCE"
        -I "$BAM"
        -O "$OUTPUT_VCF"
        --native-pair-hmm-threads "$THREADS"
    )

    if [[ "$GVCF" == true ]]; then
        HC_ARGS+=(--emit-ref-confidence GVCF)
    fi

    if [[ -n "$INTERVALS" ]]; then
        HC_ARGS+=(-L "$INTERVALS" --interval-padding 100)
    fi

    "${HC_ARGS[@]}"

    echo "GATK HaplotypeCaller complete: $OUTPUT_VCF"
fi

# ── DeepVariant path ──────────────────────────────────────────────────────────
if [[ "$CALLER" == "deepvariant" ]]; then
    echo "=== Running DeepVariant ==="

    DV_ARGS=(
        run_deepvariant
        --model_type="$MODEL_TYPE"
        --ref="$REFERENCE"
        --reads="$BAM"
        --output_vcf="$OUTPUT_VCF"
        --num_shards="$THREADS"
    )

    if [[ "$GVCF" == true ]]; then
        GVCF_OUTPUT="${OUTDIR}/${SAMPLE_NAME}.g.vcf.gz"
        DV_ARGS+=(--output_gvcf="$GVCF_OUTPUT")
    fi

    if [[ -n "$INTERVALS" ]]; then
        DV_ARGS+=(--regions="$INTERVALS")
    fi

    "${DV_ARGS[@]}"

    echo "DeepVariant complete: $OUTPUT_VCF"
fi

# ── Index output VCF ──────────────────────────────────────────────────────────
echo "=== Indexing output VCF ==="
bcftools index -t "$OUTPUT_VCF"
echo "Index: ${OUTPUT_VCF}.tbi"

# ── Variant summary statistics ────────────────────────────────────────────────
echo ""
echo "=== Variant Summary ==="
STATS_FILE="${OUTDIR}/${SAMPLE_NAME}.variant_stats.txt"

{
    echo "--- Variant Counts ---"
    bcftools stats "$OUTPUT_VCF" | grep "^SN" | cut -f3-

    echo ""
    echo "--- Ti/Tv Ratio ---"
    bcftools stats "$OUTPUT_VCF" | grep "^TSTV" | cut -f5

} | tee "$STATS_FILE"

echo ""
echo "=== Done ==="
echo "Output files:"
echo "  VCF:         $OUTPUT_VCF"
echo "  VCF index:   ${OUTPUT_VCF}.tbi"
echo "  Stats:       $STATS_FILE"
