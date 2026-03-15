#!/usr/bin/env bash
set -euo pipefail

# genome-variant-annotation/scripts/run.sh
# Annotate variants with functional effects using SnpEff or Ensembl VEP.

usage() {
    cat <<EOF
Usage: $(basename "$0") --vcf VCF [OPTIONS]

Required:
  --vcf               Filtered VCF file (.vcf.gz)

Optional:
  --annotator         Annotator: snpeff or vep (default: snpeff)
  --genome-build      Genome build (default: GRCh38)
  --cache-dir         Cache directory for annotation databases
  --outdir            Output directory (default: .)
  --db-version        SnpEff database version (default: GRCh38.105)
  --vep-plugins       Comma-separated VEP plugins (default: none)
  --vep-fields        Extra VEP output fields (default: none)
  -h, --help          Show this help message

EOF
    exit 1
}

# ── Defaults ──────────────────────────────────────────────────────────────────
VCF=""
ANNOTATOR="snpeff"
GENOME_BUILD="GRCh38"
CACHE_DIR=""
OUTDIR="."
DB_VERSION="GRCh38.105"
VEP_PLUGINS=""
VEP_FIELDS=""

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --vcf)           VCF="$2";           shift 2 ;;
        --annotator)     ANNOTATOR="$2";     shift 2 ;;
        --genome-build)  GENOME_BUILD="$2";  shift 2 ;;
        --cache-dir)     CACHE_DIR="$2";     shift 2 ;;
        --outdir)        OUTDIR="$2";        shift 2 ;;
        --db-version)    DB_VERSION="$2";    shift 2 ;;
        --vep-plugins)   VEP_PLUGINS="$2";   shift 2 ;;
        --vep-fields)    VEP_FIELDS="$2";    shift 2 ;;
        -h|--help)       usage ;;
        *)               echo "ERROR: Unknown argument: $1" >&2; usage ;;
    esac
done

# ── Validate required inputs ─────────────────────────────────────────────────
if [[ -z "$VCF" ]]; then
    echo "ERROR: --vcf is required." >&2; usage
fi
if [[ ! -f "$VCF" ]]; then
    echo "ERROR: VCF file not found: $VCF" >&2; exit 1
fi

ANNOTATOR=$(echo "$ANNOTATOR" | tr '[:upper:]' '[:lower:]')
if [[ "$ANNOTATOR" != "snpeff" && "$ANNOTATOR" != "vep" ]]; then
    echo "ERROR: --annotator must be 'snpeff' or 'vep', got: $ANNOTATOR" >&2
    exit 1
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"

SAMPLE_NAME=$(basename "$VCF" .vcf.gz)
ANNOTATED_VCF="${OUTDIR}/${SAMPLE_NAME}.annotated.vcf.gz"

# ── SnpEff path ───────────────────────────────────────────────────────────────
if [[ "$ANNOTATOR" == "snpeff" ]]; then
    echo "=== Running SnpEff annotation ==="

    SNPEFF_ARGS=(
        snpEff ann
        -v
        "$DB_VERSION"
        -stats "${OUTDIR}/${SAMPLE_NAME}.snpEff_summary.html"
        -csvStats "${OUTDIR}/${SAMPLE_NAME}.snpEff_stats.csv"
    )

    if [[ -n "$CACHE_DIR" ]]; then
        SNPEFF_ARGS+=(-dataDir "$CACHE_DIR")
    fi

    "${SNPEFF_ARGS[@]}" "$VCF" \
        | bgzip -c > "$ANNOTATED_VCF"

    echo "SnpEff annotation complete."
    echo "Summary HTML: ${OUTDIR}/${SAMPLE_NAME}.snpEff_summary.html"
fi

# ── VEP path ──────────────────────────────────────────────────────────────────
if [[ "$ANNOTATOR" == "vep" ]]; then
    echo "=== Running Ensembl VEP annotation ==="

    VEP_ARGS=(
        vep
        --input_file "$VCF"
        --output_file "${OUTDIR}/${SAMPLE_NAME}.annotated.vcf"
        --vcf
        --force_overwrite
        --cache
        --assembly "$GENOME_BUILD"
        --symbol
        --terms SO
        --hgvs
        --af_gnomade
        --stats_file "${OUTDIR}/${SAMPLE_NAME}.vep_stats.html"
    )

    if [[ -n "$CACHE_DIR" ]]; then
        VEP_ARGS+=(--dir_cache "$CACHE_DIR")
    fi

    # Add plugins if specified
    if [[ -n "$VEP_PLUGINS" ]]; then
        IFS=',' read -ra PLUGINS <<< "$VEP_PLUGINS"
        for plugin in "${PLUGINS[@]}"; do
            VEP_ARGS+=(--plugin "$plugin")
        done
    fi

    # Add extra fields if specified
    if [[ -n "$VEP_FIELDS" ]]; then
        VEP_ARGS+=(--fields "Consequence,IMPACT,SYMBOL,Gene,HGVS,$VEP_FIELDS")
    fi

    "${VEP_ARGS[@]}"

    # Compress and index
    bgzip -c "${OUTDIR}/${SAMPLE_NAME}.annotated.vcf" > "$ANNOTATED_VCF"
    rm -f "${OUTDIR}/${SAMPLE_NAME}.annotated.vcf"

    echo "VEP annotation complete."
    echo "Stats: ${OUTDIR}/${SAMPLE_NAME}.vep_stats.html"
fi

# ── Index annotated VCF ───────────────────────────────────────────────────────
echo "=== Indexing annotated VCF ==="
bcftools index -t "$ANNOTATED_VCF"

# ── Impact summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Variant Impact Summary ==="
SUMMARY_FILE="${OUTDIR}/${SAMPLE_NAME}.impact_summary.txt"

if [[ "$ANNOTATOR" == "snpeff" ]]; then
    {
        echo "--- Impact Distribution (SnpEff ANN field) ---"
        bcftools query -f '%INFO/ANN\n' "$ANNOTATED_VCF" \
            | tr ',' '\n' \
            | cut -d'|' -f3 \
            | sort | uniq -c | sort -rn

        echo ""
        echo "--- Genes with HIGH impact variants ---"
        bcftools query -f '%INFO/ANN\n' "$ANNOTATED_VCF" \
            | tr ',' '\n' \
            | awk -F'|' '$3 == "HIGH" {print $4}' \
            | sort -u
    } | tee "$SUMMARY_FILE"
fi

if [[ "$ANNOTATOR" == "vep" ]]; then
    {
        echo "--- Impact Distribution (VEP CSQ field) ---"
        bcftools query -f '%INFO/CSQ\n' "$ANNOTATED_VCF" \
            | tr ',' '\n' \
            | cut -d'|' -f3 \
            | sort | uniq -c | sort -rn

        echo ""
        echo "--- Genes with HIGH impact variants ---"
        bcftools query -f '%INFO/CSQ\n' "$ANNOTATED_VCF" \
            | tr ',' '\n' \
            | awk -F'|' '$3 == "HIGH" {print $4}' \
            | sort -u
    } | tee "$SUMMARY_FILE"
fi

echo ""
echo "=== Done ==="
echo "Output files:"
echo "  Annotated VCF:   $ANNOTATED_VCF"
echo "  VCF index:       ${ANNOTATED_VCF}.tbi"
echo "  Impact summary:  $SUMMARY_FILE"
