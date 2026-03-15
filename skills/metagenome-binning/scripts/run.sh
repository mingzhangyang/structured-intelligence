#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") --contigs FILE --bam FILE [OPTIONS]"
    echo ""
    echo "Recover MAGs from metagenomic contigs using MetaBAT2, with optional"
    echo "DAS Tool refinement and CheckM2 quality assessment."
    echo ""
    echo "Required:"
    echo "  --contigs FILE       Assembled contigs FASTA"
    echo "  --bam FILE           BAM of reads mapped to contigs"
    echo ""
    echo "Optional:"
    echo "  --outdir DIR         Output directory (default: binning_results)"
    echo "  --threads N          Number of threads (default: 4)"
    echo "  --min-contig N       Minimum contig length for binning (default: 1500)"
    echo "  --checkm2-db PATH    Path to CheckM2 database"
    echo "  --das-tool           Enable DAS Tool refinement with multiple binners"
    echo "  -h, --help           Show this help message"
    exit "${1:-0}"
}

CONTIGS=""
BAM=""
OUTDIR="binning_results"
THREADS=4
MIN_CONTIG=1500
CHECKM2_DB=""
DAS_TOOL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --contigs) CONTIGS="$2"; shift 2 ;;
        --bam) BAM="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --min-contig) MIN_CONTIG="$2"; shift 2 ;;
        --checkm2-db) CHECKM2_DB="$2"; shift 2 ;;
        --das-tool) DAS_TOOL=true; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) echo "Unexpected argument: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$CONTIGS" ]]; then
    echo "Error: --contigs is required." >&2
    usage 1
fi

if [[ -z "$BAM" ]]; then
    echo "Error: --bam is required." >&2
    usage 1
fi

mkdir -p "$OUTDIR"

METABAT_DIR="$OUTDIR/metabat2"
BINS_DIR="$OUTDIR/bins"
CHECKM2_DIR="$OUTDIR/checkm2"
DEPTH_FILE="$OUTDIR/contig_depths.txt"

mkdir -p "$METABAT_DIR" "$BINS_DIR"

# Step 1: Calculate contig coverage depth
echo "==> Calculating contig coverage depths..."
jgi_summarize_bam_contig_depths \
    --outputDepth "$DEPTH_FILE" \
    "$BAM"

# Step 2: Run MetaBAT2
echo "==> Running MetaBAT2 binning..."
metabat2 \
    -i "$CONTIGS" \
    -a "$DEPTH_FILE" \
    -o "$METABAT_DIR/bin" \
    -m "$MIN_CONTIG" \
    -t "$THREADS"

METABAT_BIN_COUNT=$(find "$METABAT_DIR" -name "bin.*.fa" 2>/dev/null | wc -l)
echo "MetaBAT2 produced $METABAT_BIN_COUNT bins."

# Step 3: Optionally run additional binners and DAS Tool
if $DAS_TOOL; then
    echo "==> Running MaxBin2 for DAS Tool input..."
    MAXBIN_DIR="$OUTDIR/maxbin2"
    mkdir -p "$MAXBIN_DIR"

    # Generate abundance file for MaxBin2 from depth file
    awk 'NR>1 {print $1"\t"$3}' "$DEPTH_FILE" > "$OUTDIR/maxbin_abundance.txt"

    run_MaxBin.pl \
        -contig "$CONTIGS" \
        -abund "$OUTDIR/maxbin_abundance.txt" \
        -out "$MAXBIN_DIR/bin" \
        -thread "$THREADS" \
        -min_contig_length "$MIN_CONTIG" || true

    echo "==> Running CONCOCT for DAS Tool input..."
    CONCOCT_DIR="$OUTDIR/concoct"
    mkdir -p "$CONCOCT_DIR"

    # Cut contigs into 10kb chunks for CONCOCT
    cut_up_fasta.py "$CONTIGS" -c 10000 -o 0 --merge_last \
        -b "$CONCOCT_DIR/contigs_10K.bed" > "$CONCOCT_DIR/contigs_10K.fa"

    concoct_coverage_table.py "$CONCOCT_DIR/contigs_10K.bed" "$BAM" \
        > "$CONCOCT_DIR/coverage_table.tsv"

    concoct \
        --composition_file "$CONCOCT_DIR/contigs_10K.fa" \
        --coverage_file "$CONCOCT_DIR/coverage_table.tsv" \
        -b "$CONCOCT_DIR/" \
        -t "$THREADS" \
        -l "$MIN_CONTIG" || true

    merge_cutup_clustering.py "$CONCOCT_DIR/clustering_gt${MIN_CONTIG}.csv" \
        > "$CONCOCT_DIR/clustering_merged.csv" || true

    extract_fasta_bins.py "$CONTIGS" "$CONCOCT_DIR/clustering_merged.csv" \
        --output_path "$CONCOCT_DIR/bins/" || true

    # Step 4: Run DAS Tool
    echo "==> Running DAS Tool to select best non-redundant bin set..."
    DASTOOL_DIR="$OUTDIR/dastool"
    mkdir -p "$DASTOOL_DIR"

    # Generate scaffold-to-bin tables
    Fasta_to_Contig2Bin.sh -i "$METABAT_DIR" -e fa > "$DASTOOL_DIR/metabat2_s2b.tsv"

    BINNER_LABELS="metabat2"
    BINNER_FILES="$DASTOOL_DIR/metabat2_s2b.tsv"

    if [[ -d "$MAXBIN_DIR" ]] && ls "$MAXBIN_DIR"/bin.*.fasta &>/dev/null; then
        Fasta_to_Contig2Bin.sh -i "$MAXBIN_DIR" -e fasta > "$DASTOOL_DIR/maxbin2_s2b.tsv"
        BINNER_LABELS="$BINNER_LABELS,maxbin2"
        BINNER_FILES="$BINNER_FILES,$DASTOOL_DIR/maxbin2_s2b.tsv"
    fi

    if [[ -d "$CONCOCT_DIR/bins" ]] && ls "$CONCOCT_DIR/bins"/*.fa &>/dev/null; then
        Fasta_to_Contig2Bin.sh -i "$CONCOCT_DIR/bins" -e fa > "$DASTOOL_DIR/concoct_s2b.tsv"
        BINNER_LABELS="$BINNER_LABELS,concoct"
        BINNER_FILES="$BINNER_FILES,$DASTOOL_DIR/concoct_s2b.tsv"
    fi

    DAS_Tool \
        -i "$BINNER_FILES" \
        -l "$BINNER_LABELS" \
        -c "$CONTIGS" \
        -o "$DASTOOL_DIR/dastool" \
        -t "$THREADS" \
        --write_bins

    # Copy DAS Tool refined bins to final bins directory
    if [[ -d "$DASTOOL_DIR/dastool_DASTool_bins" ]]; then
        cp "$DASTOOL_DIR/dastool_DASTool_bins"/*.fa "$BINS_DIR/" 2>/dev/null || true
    fi
else
    # Copy MetaBAT2 bins to final bins directory
    cp "$METABAT_DIR"/bin.*.fa "$BINS_DIR/" 2>/dev/null || true
fi

FINAL_BIN_COUNT=$(find "$BINS_DIR" -name "*.fa" 2>/dev/null | wc -l)
echo "Final bin count: $FINAL_BIN_COUNT"

# Step 5: Run CheckM2 quality assessment
echo "==> Running CheckM2 quality assessment..."
mkdir -p "$CHECKM2_DIR"

CHECKM2_ARGS=(
    predict
    --input "$BINS_DIR"
    --output-directory "$CHECKM2_DIR"
    -x fa
    --threads "$THREADS"
    --force
)

if [[ -n "$CHECKM2_DB" ]]; then
    CHECKM2_ARGS+=(--database_path "$CHECKM2_DB")
fi

checkm2 "${CHECKM2_ARGS[@]}"

# Step 6: Classify bins by MIMAG standards
echo "==> Classifying bins by MIMAG standards..."
SUMMARY_FILE="$OUTDIR/bin_summary.txt"
QUALITY_REPORT="$CHECKM2_DIR/quality_report.tsv"

if [[ -f "$QUALITY_REPORT" ]]; then
    awk -F'\t' '
    BEGIN {
        printf "%-20s  %12s  %14s  %s\n", "Bin", "Completeness", "Contamination", "Classification"
        printf "%-20s  %12s  %14s  %s\n", "---", "------------", "-------------", "--------------"
        hq = 0; mq = 0; lq = 0
    }
    NR > 1 {
        bin = $1
        comp = $2
        cont = $3
        if (comp >= 90 && cont < 5) {
            class = "High-quality"
            hq++
        } else if (comp >= 50 && cont < 10) {
            class = "Medium-quality"
            mq++
        } else {
            class = "Low-quality"
            lq++
        }
        printf "%-20s  %11.1f%%  %13.1f%%  %s\n", bin, comp, cont, class
    }
    END {
        printf "\nMIMAG Summary\n"
        printf "=============\n"
        printf "High-quality:    %d\n", hq
        printf "Medium-quality:  %d\n", mq
        printf "Low-quality:     %d\n", lq
        printf "Total bins:      %d\n", hq + mq + lq
    }
    ' "$QUALITY_REPORT" | tee "$SUMMARY_FILE"
else
    echo "Warning: CheckM2 quality report not found." >&2
fi

echo ""
echo "==> Binning complete."
echo "==> Output files:"
echo "  Bins directory:   $BINS_DIR/"
echo "  CheckM2 report:   $QUALITY_REPORT"
echo "  Bin summary:      $SUMMARY_FILE"
