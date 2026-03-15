#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") [-1 READ1 [-2 READ2]] [--contigs FILE] [OPTIONS]"
    echo ""
    echo "Functional annotation of metagenomic data."
    echo ""
    echo "Input (depends on --tool):"
    echo "  -1 FILE               Forward reads FASTQ (for HUMAnN)"
    echo "  -2 FILE               Reverse reads FASTQ (for HUMAnN, optional)"
    echo "  --contigs FILE         Contigs or MAG FASTA (for Prokka/eggNOG)"
    echo ""
    echo "Options:"
    echo "  --tool STR             Tool: humann, prokka, or eggnog (default: humann)"
    echo "  --db PATH              Database path (HUMAnN nucleotide DB or eggNOG DB)"
    echo "  --taxonomic-profile F  Taxonomic profile to guide HUMAnN search"
    echo "  --kingdom STR          Prokka kingdom (default: Bacteria)"
    echo "  --outdir DIR           Output directory (default: functional_profiling_results)"
    echo "  --threads N            Number of threads (default: 4)"
    echo "  -h, --help             Show this help message"
    exit "${1:-0}"
}

READ1=""
READ2=""
CONTIGS=""
TOOL="humann"
DB=""
TAXONOMIC_PROFILE=""
KINGDOM="Bacteria"
OUTDIR="functional_profiling_results"
THREADS=4

while [[ $# -gt 0 ]]; do
    case "$1" in
        -1) READ1="$2"; shift 2 ;;
        -2) READ2="$2"; shift 2 ;;
        --contigs) CONTIGS="$2"; shift 2 ;;
        --tool) TOOL="$2"; shift 2 ;;
        --db) DB="$2"; shift 2 ;;
        --taxonomic-profile) TAXONOMIC_PROFILE="$2"; shift 2 ;;
        --kingdom) KINGDOM="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) echo "Unexpected argument: $1" >&2; usage 1 ;;
    esac
done

if [[ "$TOOL" != "humann" && "$TOOL" != "prokka" && "$TOOL" != "eggnog" ]]; then
    echo "Error: --tool must be 'humann', 'prokka', or 'eggnog'." >&2
    exit 1
fi

if [[ "$TOOL" == "humann" && -z "$READ1" ]]; then
    echo "Error: -1 READ1 is required for HUMAnN." >&2
    usage 1
fi

if [[ ("$TOOL" == "prokka" || "$TOOL" == "eggnog") && -z "$CONTIGS" ]]; then
    echo "Error: --contigs is required for Prokka/eggNOG." >&2
    usage 1
fi

mkdir -p "$OUTDIR"

SUMMARY_FILE="$OUTDIR/functional_summary.txt"

if [[ "$TOOL" == "humann" ]]; then
    # Determine sample name
    SAMPLE=$(basename "$READ1" | sed -E 's/(_R1)?(_001)?(_hostdepleted)?\.(fastq|fq)(\.gz)?$//')

    # If paired-end, concatenate reads for HUMAnN (HUMAnN expects a single input file)
    INPUT_FILE="$READ1"
    if [[ -n "$READ2" ]]; then
        echo "==> Concatenating paired-end reads for HUMAnN input..."
        CONCAT_FILE="$OUTDIR/${SAMPLE}_concat.fastq.gz"
        cat "$READ1" "$READ2" > "$CONCAT_FILE"
        INPUT_FILE="$CONCAT_FILE"
    fi

    echo "==> Running HUMAnN 3 functional profiling..."
    HUMANN_ARGS=(
        --input "$INPUT_FILE"
        --output "$OUTDIR/humann"
        --threads "$THREADS"
    )

    if [[ -n "$DB" ]]; then
        HUMANN_ARGS+=(--nucleotide-database "$DB")
    fi

    if [[ -n "$TAXONOMIC_PROFILE" ]]; then
        HUMANN_ARGS+=(--taxonomic-profile "$TAXONOMIC_PROFILE")
    fi

    humann "${HUMANN_ARGS[@]}"

    # Locate HUMAnN output files
    GENEFAMILIES=$(find "$OUTDIR/humann" -name "*_genefamilies.tsv" | head -1)
    PATHABUNDANCE=$(find "$OUTDIR/humann" -name "*_pathabundance.tsv" | head -1)
    PATHCOVERAGE=$(find "$OUTDIR/humann" -name "*_pathcoverage.tsv" | head -1)

    # Normalize gene families to CPM
    if [[ -n "$GENEFAMILIES" ]]; then
        echo "==> Normalizing gene families to CPM..."
        humann_renorm_table \
            --input "$GENEFAMILIES" \
            --output "$OUTDIR/${SAMPLE}_genefamilies_cpm.tsv" \
            --units cpm
    fi

    # Normalize pathway abundance to relative abundance
    if [[ -n "$PATHABUNDANCE" ]]; then
        echo "==> Normalizing pathway abundance to relative abundance..."
        humann_renorm_table \
            --input "$PATHABUNDANCE" \
            --output "$OUTDIR/${SAMPLE}_pathabundance_relab.tsv" \
            --units relab
    fi

    # Generate summary
    echo "==> Generating functional summary..."
    {
        echo "HUMAnN 3 Functional Summary"
        echo "==========================="
        echo "Sample: $SAMPLE"
        echo ""

        if [[ -n "$GENEFAMILIES" ]]; then
            GF_COUNT=$(grep -v "^#" "$GENEFAMILIES" | grep -v "UNMAPPED\|UNGROUPED" | wc -l)
            echo "Gene families detected: $GF_COUNT"
        fi

        if [[ -n "$PATHABUNDANCE" ]]; then
            PW_COUNT=$(grep -v "^#" "$PATHABUNDANCE" | grep -v "UNMAPPED\|UNINTEGRATED" | grep -v "|" | wc -l)
            echo "Pathways detected:      $PW_COUNT"
            echo ""
            echo "Top 20 pathways by abundance:"
            grep -v "^#" "$PATHABUNDANCE" \
                | grep -v "UNMAPPED\|UNINTEGRATED" \
                | grep -v "|" \
                | sort -t$'\t' -k2 -rn \
                | head -20 \
                | awk -F'\t' '{printf "  %10.4f  %s\n", $2, $1}'
        fi
    } | tee "$SUMMARY_FILE"

    # Clean up concatenated file
    if [[ -n "$READ2" && -f "$CONCAT_FILE" ]]; then
        rm -f "$CONCAT_FILE"
    fi

    echo ""
    echo "==> HUMAnN output directory: $OUTDIR/humann/"

elif [[ "$TOOL" == "prokka" ]]; then
    SAMPLE=$(basename "$CONTIGS" | sed -E 's/\.(fasta|fa|fna)(\.gz)?$//')

    echo "==> Running Prokka gene prediction and annotation..."
    PROKKA_DIR="$OUTDIR/prokka"

    prokka \
        --outdir "$PROKKA_DIR" \
        --prefix "$SAMPLE" \
        --kingdom "$KINGDOM" \
        --cpus "$THREADS" \
        --force \
        "$CONTIGS"

    # Generate summary
    echo "==> Generating functional summary..."
    {
        echo "Prokka Annotation Summary"
        echo "========================="
        echo "Sample: $SAMPLE"
        echo "Kingdom: $KINGDOM"
        echo ""

        if [[ -f "$PROKKA_DIR/${SAMPLE}.txt" ]]; then
            cat "$PROKKA_DIR/${SAMPLE}.txt"
        fi

        echo ""
        echo "Output files:"
        echo "  GFF: $PROKKA_DIR/${SAMPLE}.gff"
        echo "  GBK: $PROKKA_DIR/${SAMPLE}.gbk"
        echo "  FAA: $PROKKA_DIR/${SAMPLE}.faa"
        echo "  FFN: $PROKKA_DIR/${SAMPLE}.ffn"
    } | tee "$SUMMARY_FILE"

    echo ""
    echo "==> Prokka output directory: $PROKKA_DIR/"

elif [[ "$TOOL" == "eggnog" ]]; then
    SAMPLE=$(basename "$CONTIGS" | sed -E 's/\.(fasta|fa|faa|fna)(\.gz)?$//')

    echo "==> Running eggNOG-mapper annotation..."
    EGGNOG_DIR="$OUTDIR/eggnog"
    mkdir -p "$EGGNOG_DIR"

    EGGNOG_ARGS=(
        -i "$CONTIGS"
        --output "$EGGNOG_DIR/$SAMPLE"
        --cpu "$THREADS"
        -m diamond
        --override
    )

    if [[ -n "$DB" ]]; then
        EGGNOG_ARGS+=(--data_dir "$DB")
    fi

    emapper.py "${EGGNOG_ARGS[@]}"

    # Generate summary
    ANNOTATIONS="$EGGNOG_DIR/${SAMPLE}.emapper.annotations"
    echo "==> Generating functional summary..."
    {
        echo "eggNOG-mapper Annotation Summary"
        echo "================================"
        echo "Sample: $SAMPLE"
        echo ""

        if [[ -f "$ANNOTATIONS" ]]; then
            TOTAL_ANNOT=$(grep -v "^#" "$ANNOTATIONS" | wc -l)
            echo "Total annotated sequences: $TOTAL_ANNOT"

            # Count COG categories
            COG_COUNT=$(grep -v "^#" "$ANNOTATIONS" | awk -F'\t' '$7 != "-" && $7 != "" {count++} END {print count+0}')
            echo "Sequences with COG assignment: $COG_COUNT"

            # Count KEGG annotations
            KEGG_COUNT=$(grep -v "^#" "$ANNOTATIONS" | awk -F'\t' '$12 != "-" && $12 != "" {count++} END {print count+0}')
            echo "Sequences with KEGG assignment: $KEGG_COUNT"

            # Count GO annotations
            GO_COUNT=$(grep -v "^#" "$ANNOTATIONS" | awk -F'\t' '$10 != "-" && $10 != "" {count++} END {print count+0}')
            echo "Sequences with GO assignment: $GO_COUNT"

            echo ""
            echo "COG functional category distribution:"
            grep -v "^#" "$ANNOTATIONS" \
                | awk -F'\t' '$7 != "-" && $7 != "" {
                    n = split($7, cats, "")
                    for (i = 1; i <= n; i++) count[cats[i]]++
                }
                END {
                    for (c in count) printf "  %s: %d\n", c, count[c]
                }' \
                | sort -t: -k2 -rn \
                | head -20
        fi
    } | tee "$SUMMARY_FILE"

    echo ""
    echo "==> eggNOG output directory: $EGGNOG_DIR/"
fi

echo ""
echo "==> Functional profiling complete."
echo "  Summary: $SUMMARY_FILE"
