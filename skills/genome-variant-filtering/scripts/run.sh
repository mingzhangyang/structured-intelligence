#!/usr/bin/env bash
set -euo pipefail

# genome-variant-filtering/scripts/run.sh
# Filter raw variant calls using GATK hard filters, VQSR, or bcftools expressions.

usage() {
    cat <<EOF
Usage: $(basename "$0") --vcf VCF --ref REFERENCE [OPTIONS]

Required:
  --vcf               Raw VCF file (.vcf.gz)
  --ref               Reference FASTA

Optional:
  --strategy          Filter strategy: vqsr, hard, or bcftools (default: hard)
  --outdir            Output directory (default: .)
  --filter-expr       Custom bcftools filter expression (for bcftools strategy)
  --hapmap            HapMap resource VCF (for VQSR)
  --omni              Omni resource VCF (for VQSR)
  --thousandg         1000 Genomes resource VCF (for VQSR)
  --dbsnp             dbSNP resource VCF (for VQSR)
  --snp-sensitivity   VQSR truth sensitivity for SNPs (default: 99.5)
  --indel-sensitivity VQSR truth sensitivity for indels (default: 99.0)
  -h, --help          Show this help message

EOF
    exit 1
}

# ── Defaults ──────────────────────────────────────────────────────────────────
VCF=""
REFERENCE=""
STRATEGY="hard"
OUTDIR="."
FILTER_EXPR=""
HAPMAP=""
OMNI=""
THOUSANDG=""
DBSNP=""
SNP_SENSITIVITY="99.5"
INDEL_SENSITIVITY="99.0"

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --vcf)              VCF="$2";                shift 2 ;;
        --ref)              REFERENCE="$2";           shift 2 ;;
        --strategy)         STRATEGY="$2";            shift 2 ;;
        --outdir)           OUTDIR="$2";              shift 2 ;;
        --filter-expr)      FILTER_EXPR="$2";         shift 2 ;;
        --hapmap)           HAPMAP="$2";              shift 2 ;;
        --omni)             OMNI="$2";                shift 2 ;;
        --thousandg)        THOUSANDG="$2";            shift 2 ;;
        --dbsnp)            DBSNP="$2";               shift 2 ;;
        --snp-sensitivity)  SNP_SENSITIVITY="$2";     shift 2 ;;
        --indel-sensitivity) INDEL_SENSITIVITY="$2";  shift 2 ;;
        -h|--help)          usage ;;
        *)                  echo "ERROR: Unknown argument: $1" >&2; usage ;;
    esac
done

# ── Validate required inputs ─────────────────────────────────────────────────
if [[ -z "$VCF" ]]; then
    echo "ERROR: --vcf is required." >&2; usage
fi
if [[ -z "$REFERENCE" ]]; then
    echo "ERROR: --ref is required." >&2; usage
fi
if [[ ! -f "$VCF" ]]; then
    echo "ERROR: VCF file not found: $VCF" >&2; exit 1
fi
if [[ ! -f "$REFERENCE" ]]; then
    echo "ERROR: Reference FASTA not found: $REFERENCE" >&2; exit 1
fi

STRATEGY=$(echo "$STRATEGY" | tr '[:upper:]' '[:lower:]')
if [[ "$STRATEGY" != "hard" && "$STRATEGY" != "vqsr" && "$STRATEGY" != "bcftools" ]]; then
    echo "ERROR: --strategy must be 'hard', 'vqsr', or 'bcftools', got: $STRATEGY" >&2
    exit 1
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"

SAMPLE_NAME=$(basename "$VCF" .vcf.gz)
FILTERED_VCF="${OUTDIR}/${SAMPLE_NAME}.filtered.vcf.gz"

# Count variants before filtering
echo "=== Counting variants before filtering ==="
TOTAL_BEFORE=$(bcftools view -H "$VCF" | wc -l)
echo "Total variants before filtering: $TOTAL_BEFORE"

# ── Hard filter strategy ──────────────────────────────────────────────────────
if [[ "$STRATEGY" == "hard" ]]; then
    echo "=== Applying GATK hard filters ==="

    SNP_VCF="${OUTDIR}/${SAMPLE_NAME}.snps.vcf.gz"
    INDEL_VCF="${OUTDIR}/${SAMPLE_NAME}.indels.vcf.gz"
    SNP_FILTERED="${OUTDIR}/${SAMPLE_NAME}.snps.filtered.vcf.gz"
    INDEL_FILTERED="${OUTDIR}/${SAMPLE_NAME}.indels.filtered.vcf.gz"

    # Select SNPs
    echo "--- Selecting SNPs ---"
    gatk SelectVariants \
        -R "$REFERENCE" \
        -V "$VCF" \
        --select-type-to-include SNP \
        -O "$SNP_VCF"

    # Select indels
    echo "--- Selecting indels ---"
    gatk SelectVariants \
        -R "$REFERENCE" \
        -V "$VCF" \
        --select-type-to-include INDEL \
        -O "$INDEL_VCF"

    # Hard-filter SNPs
    echo "--- Hard-filtering SNPs ---"
    gatk VariantFiltration \
        -R "$REFERENCE" \
        -V "$SNP_VCF" \
        --filter-expression "QD < 2.0" --filter-name "LowQD" \
        --filter-expression "FS > 60.0" --filter-name "HighFS" \
        --filter-expression "MQ < 40.0" --filter-name "LowMQ" \
        --filter-expression "MQRankSum < -12.5" --filter-name "LowMQRankSum" \
        --filter-expression "ReadPosRankSum < -8.0" --filter-name "LowReadPosRankSum" \
        -O "$SNP_FILTERED"

    # Hard-filter indels
    echo "--- Hard-filtering indels ---"
    gatk VariantFiltration \
        -R "$REFERENCE" \
        -V "$INDEL_VCF" \
        --filter-expression "QD < 2.0" --filter-name "LowQD" \
        --filter-expression "FS > 200.0" --filter-name "HighFS" \
        --filter-expression "ReadPosRankSum < -20.0" --filter-name "LowReadPosRankSum" \
        -O "$INDEL_FILTERED"

    # Merge filtered SNPs and indels
    echo "--- Merging filtered SNPs and indels ---"
    gatk MergeVcfs \
        -I "$SNP_FILTERED" \
        -I "$INDEL_FILTERED" \
        -O "$FILTERED_VCF"

    # Clean up intermediates
    rm -f "$SNP_VCF" "${SNP_VCF}.tbi" "$INDEL_VCF" "${INDEL_VCF}.tbi"
    rm -f "$SNP_FILTERED" "${SNP_FILTERED}.tbi" "$INDEL_FILTERED" "${INDEL_FILTERED}.tbi"
fi

# ── VQSR strategy ────────────────────────────────────────────────────────────
if [[ "$STRATEGY" == "vqsr" ]]; then
    echo "=== Applying VQSR ==="

    # Validate VQSR resources
    if [[ -z "$HAPMAP" || -z "$OMNI" || -z "$THOUSANDG" || -z "$DBSNP" ]]; then
        echo "ERROR: VQSR requires --hapmap, --omni, --thousandg, and --dbsnp resource VCFs." >&2
        exit 1
    fi

    SNP_RECAL="${OUTDIR}/${SAMPLE_NAME}.snps.recal"
    SNP_TRANCHES="${OUTDIR}/${SAMPLE_NAME}.snps.tranches"
    INDEL_RECAL="${OUTDIR}/${SAMPLE_NAME}.indels.recal"
    INDEL_TRANCHES="${OUTDIR}/${SAMPLE_NAME}.indels.tranches"
    SNP_VQSR_VCF="${OUTDIR}/${SAMPLE_NAME}.snps.vqsr.vcf.gz"

    # SNP recalibration
    echo "--- SNP VariantRecalibrator ---"
    gatk VariantRecalibrator \
        -R "$REFERENCE" \
        -V "$VCF" \
        --resource:hapmap,known=false,training=true,truth=true,prior=15.0 "$HAPMAP" \
        --resource:omni,known=false,training=true,truth=false,prior=12.0 "$OMNI" \
        --resource:1000G,known=false,training=true,truth=false,prior=10.0 "$THOUSANDG" \
        --resource:dbsnp,known=true,training=false,truth=false,prior=2.0 "$DBSNP" \
        -an QD -an MQ -an MQRankSum -an ReadPosRankSum -an FS -an SOR \
        -mode SNP \
        -O "$SNP_RECAL" \
        --tranches-file "$SNP_TRANCHES"

    # Apply SNP VQSR
    echo "--- Apply SNP VQSR ---"
    gatk ApplyVQSR \
        -R "$REFERENCE" \
        -V "$VCF" \
        --recal-file "$SNP_RECAL" \
        --tranches-file "$SNP_TRANCHES" \
        --truth-sensitivity-filter-level "$SNP_SENSITIVITY" \
        -mode SNP \
        -O "$SNP_VQSR_VCF"

    # Indel recalibration
    echo "--- Indel VariantRecalibrator ---"
    gatk VariantRecalibrator \
        -R "$REFERENCE" \
        -V "$SNP_VQSR_VCF" \
        --resource:mills,known=false,training=true,truth=true,prior=12.0 "$THOUSANDG" \
        --resource:dbsnp,known=true,training=false,truth=false,prior=2.0 "$DBSNP" \
        -an QD -an MQRankSum -an ReadPosRankSum -an FS -an SOR \
        -mode INDEL \
        -O "$INDEL_RECAL" \
        --tranches-file "$INDEL_TRANCHES"

    # Apply indel VQSR
    echo "--- Apply Indel VQSR ---"
    gatk ApplyVQSR \
        -R "$REFERENCE" \
        -V "$SNP_VQSR_VCF" \
        --recal-file "$INDEL_RECAL" \
        --tranches-file "$INDEL_TRANCHES" \
        --truth-sensitivity-filter-level "$INDEL_SENSITIVITY" \
        -mode INDEL \
        -O "$FILTERED_VCF"

    # Clean up intermediates
    rm -f "$SNP_RECAL" "${SNP_RECAL}.idx" "$SNP_TRANCHES"
    rm -f "$INDEL_RECAL" "${INDEL_RECAL}.idx" "$INDEL_TRANCHES"
    rm -f "$SNP_VQSR_VCF" "${SNP_VQSR_VCF}.tbi"
fi

# ── bcftools strategy ─────────────────────────────────────────────────────────
if [[ "$STRATEGY" == "bcftools" ]]; then
    echo "=== Applying bcftools filter ==="

    if [[ -z "$FILTER_EXPR" ]]; then
        # Default bcftools filter: quality and depth
        FILTER_EXPR="QUAL<30 || DP<10"
        echo "No --filter-expr provided, using default: $FILTER_EXPR"
    fi

    bcftools filter \
        -e "$FILTER_EXPR" \
        -s "FILTER" \
        -Oz -o "$FILTERED_VCF" \
        "$VCF"
fi

# ── Index output VCF ──────────────────────────────────────────────────────────
echo "=== Indexing filtered VCF ==="
bcftools index -t "$FILTERED_VCF"

# ── Filter summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Filter Summary ==="
STATS_FILE="${OUTDIR}/${SAMPLE_NAME}.filter_summary.txt"

TOTAL_AFTER=$(bcftools view -H "$FILTERED_VCF" | wc -l)
PASS_COUNT=$(bcftools view -H -f PASS "$FILTERED_VCF" | wc -l)
FILTERED_COUNT=$((TOTAL_AFTER - PASS_COUNT))

{
    echo "Strategy:             $STRATEGY"
    echo "Variants before:      $TOTAL_BEFORE"
    echo "Variants after:       $TOTAL_AFTER"
    echo "PASS:                 $PASS_COUNT"
    echo "Filtered:             $FILTERED_COUNT"
    if [[ "$TOTAL_BEFORE" -gt 0 ]]; then
        PASS_RATE=$(awk "BEGIN {printf \"%.2f\", ($PASS_COUNT / $TOTAL_BEFORE) * 100}")
        echo "Pass rate:            ${PASS_RATE}%"
    fi

    echo ""
    echo "--- Filter category breakdown ---"
    bcftools query -f '%FILTER\n' "$FILTERED_VCF" | sort | uniq -c | sort -rn
} | tee "$STATS_FILE"

echo ""
echo "=== Done ==="
echo "Output files:"
echo "  Filtered VCF:    $FILTERED_VCF"
echo "  VCF index:       ${FILTERED_VCF}.tbi"
echo "  Filter summary:  $STATS_FILE"
