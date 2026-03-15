#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") -1 READ1 [-2 READ2] --db PATH [OPTIONS]"
    echo ""
    echo "Profile microbial community composition from metagenomic reads."
    echo ""
    echo "Required:"
    echo "  -1 FILE          Forward reads FASTQ"
    echo "  --db PATH        Database path (Kraken2 or MetaPhlAn)"
    echo ""
    echo "Optional:"
    echo "  -2 FILE          Reverse reads FASTQ (PE mode)"
    echo "  --profiler STR   Profiler: kraken2 or metaphlan (default: kraken2)"
    echo "  --bracken-db PATH  Bracken database path"
    echo "  --bracken-len N  Read length for Bracken (e.g., 150)"
    echo "  --level CHAR     Taxonomic level for Bracken: S, G, P, etc. (default: S)"
    echo "  --outdir DIR     Output directory (default: taxonomic_profiling_results)"
    echo "  --threads N      Number of threads (default: 4)"
    echo "  --confidence F   Kraken2 confidence threshold (default: 0.0)"
    echo "  -h, --help       Show this help message"
    exit "${1:-0}"
}

READ1=""
READ2=""
DB=""
PROFILER="kraken2"
BRACKEN_DB=""
BRACKEN_LEN=""
LEVEL="S"
OUTDIR="taxonomic_profiling_results"
THREADS=4
CONFIDENCE="0.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -1) READ1="$2"; shift 2 ;;
        -2) READ2="$2"; shift 2 ;;
        --db) DB="$2"; shift 2 ;;
        --profiler) PROFILER="$2"; shift 2 ;;
        --bracken-db) BRACKEN_DB="$2"; shift 2 ;;
        --bracken-len) BRACKEN_LEN="$2"; shift 2 ;;
        --level) LEVEL="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --confidence) CONFIDENCE="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) echo "Unexpected argument: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$READ1" ]]; then
    echo "Error: -1 READ1 is required." >&2
    usage 1
fi

if [[ -z "$DB" ]]; then
    echo "Error: --db is required." >&2
    usage 1
fi

if [[ "$PROFILER" != "kraken2" && "$PROFILER" != "metaphlan" ]]; then
    echo "Error: --profiler must be 'kraken2' or 'metaphlan'." >&2
    exit 1
fi

mkdir -p "$OUTDIR"

SAMPLE=$(basename "$READ1" | sed -E 's/(_R1)?(_001)?(_hostdepleted)?\.(fastq|fq)(\.gz)?$//')

if [[ "$PROFILER" == "kraken2" ]]; then
    echo "==> Running Kraken2 taxonomic classification..."
    KRAKEN_ARGS=(
        --db "$DB"
        --threads "$THREADS"
        --confidence "$CONFIDENCE"
        --report "$OUTDIR/${SAMPLE}_kraken2_report.txt"
        --output "$OUTDIR/${SAMPLE}_kraken2_output.txt"
    )

    if [[ -n "$READ2" ]]; then
        KRAKEN_ARGS+=(--paired "$READ1" "$READ2")
    else
        KRAKEN_ARGS+=("$READ1")
    fi

    kraken2 "${KRAKEN_ARGS[@]}"

    # Calculate classification rate from Kraken2 output
    TOTAL=$(wc -l < "$OUTDIR/${SAMPLE}_kraken2_output.txt")
    CLASSIFIED=$(grep -c "^C" "$OUTDIR/${SAMPLE}_kraken2_output.txt" || true)
    if [[ "$TOTAL" -gt 0 ]]; then
        CLASS_RATE=$(awk "BEGIN {printf \"%.2f\", ($CLASSIFIED / $TOTAL) * 100}")
    else
        CLASS_RATE="0.00"
    fi
    echo "Classification rate: ${CLASS_RATE}%"

    # Run Bracken if database and read length are provided
    if [[ -n "$BRACKEN_DB" && -n "$BRACKEN_LEN" ]]; then
        echo "==> Running Bracken abundance re-estimation at level $LEVEL..."
        bracken \
            -d "$BRACKEN_DB" \
            -i "$OUTDIR/${SAMPLE}_kraken2_report.txt" \
            -o "$OUTDIR/${SAMPLE}_bracken.txt" \
            -w "$OUTDIR/${SAMPLE}_bracken_report.txt" \
            -r "$BRACKEN_LEN" \
            -l "$LEVEL"
        echo "Bracken output: $OUTDIR/${SAMPLE}_bracken.txt"
    fi

    # Parse top taxa from Kraken2 report
    echo ""
    echo "==> Top 20 taxa by percentage:"
    sort -t$'\t' -k1 -rn "$OUTDIR/${SAMPLE}_kraken2_report.txt" \
        | head -20 \
        | awk -F'\t' '{printf "  %6.2f%%  %s %s\n", $1, $4, $6}'

elif [[ "$PROFILER" == "metaphlan" ]]; then
    echo "==> Running MetaPhlAn taxonomic profiling..."
    METAPHLAN_ARGS=(
        --input_type fastq
        --nproc "$THREADS"
        --bowtie2db "$DB"
        -o "$OUTDIR/${SAMPLE}_metaphlan_profile.txt"
    )

    if [[ -n "$READ2" ]]; then
        metaphlan "$READ1","$READ2" "${METAPHLAN_ARGS[@]}"
    else
        metaphlan "$READ1" "${METAPHLAN_ARGS[@]}"
    fi

    echo "MetaPhlAn profile: $OUTDIR/${SAMPLE}_metaphlan_profile.txt"

    # Parse top taxa from MetaPhlAn output
    echo ""
    echo "==> Top 20 taxa by relative abundance:"
    grep -v "^#" "$OUTDIR/${SAMPLE}_metaphlan_profile.txt" \
        | grep "s__" \
        | sort -t$'\t' -k2 -rn \
        | head -20 \
        | awk -F'\t' '{printf "  %6.2f%%  %s\n", $2, $1}'
fi

# Compute diversity metrics from the report
echo ""
echo "==> Computing alpha diversity metrics..."

DIVERSITY_FILE="$OUTDIR/${SAMPLE}_diversity.txt"

if [[ "$PROFILER" == "kraken2" ]]; then
    # Use Bracken output if available, otherwise Kraken2 report
    if [[ -f "$OUTDIR/${SAMPLE}_bracken.txt" ]]; then
        ABUND_FILE="$OUTDIR/${SAMPLE}_bracken.txt"
        # Bracken output: fraction_total_reads is column 7
        awk -F'\t' 'NR>1 && $7>0 {print $7}' "$ABUND_FILE" > "$OUTDIR/${SAMPLE}_fractions.tmp"
    else
        ABUND_FILE="$OUTDIR/${SAMPLE}_kraken2_report.txt"
        # Kraken2 report: percentage is column 1, rank is column 4
        awk -F'\t' '$4=="S" && $1>0 {print $1/100}' "$ABUND_FILE" > "$OUTDIR/${SAMPLE}_fractions.tmp"
    fi
else
    grep -v "^#" "$OUTDIR/${SAMPLE}_metaphlan_profile.txt" \
        | grep "s__" \
        | awk -F'\t' '$2>0 {print $2/100}' > "$OUTDIR/${SAMPLE}_fractions.tmp"
fi

# Shannon and Simpson diversity
awk '
BEGIN { shannon=0; simpson=0 }
{
    p = $1
    if (p > 0) {
        shannon -= p * log(p)
        simpson += p * p
    }
}
END {
    printf "Species detected:  %d\n", NR
    printf "Shannon diversity: %.4f\n", shannon
    printf "Simpson diversity: %.4f\n", 1 - simpson
}
' "$OUTDIR/${SAMPLE}_fractions.tmp" | tee "$DIVERSITY_FILE"

rm -f "$OUTDIR/${SAMPLE}_fractions.tmp"

echo ""
echo "==> Taxonomic profiling complete."
echo "Output directory: $OUTDIR/"
