#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") -1 READ1 [-2 READ2] [OPTIONS]"
    echo ""
    echo "De novo assembly of metagenomic contigs from short reads."
    echo ""
    echo "Required:"
    echo "  -1 FILE            Forward reads FASTQ"
    echo ""
    echo "Optional:"
    echo "  -2 FILE            Reverse reads FASTQ (PE mode)"
    echo "  --assembler STR    Assembler: megahit or metaspades (default: megahit)"
    echo "  --outdir DIR       Output directory (default: assembly_results)"
    echo "  --threads N        Number of threads (default: 4)"
    echo "  --memory N         Memory limit in GB (default: 16)"
    echo "  --min-length N     Minimum contig length in bp (default: 1000)"
    echo "  --kmer-sizes STR   Comma-separated k-mer sizes for metaSPAdes"
    echo "  -h, --help         Show this help message"
    exit "${1:-0}"
}

READ1=""
READ2=""
ASSEMBLER="megahit"
OUTDIR="assembly_results"
THREADS=4
MEMORY=16
MIN_LENGTH=1000
KMER_SIZES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -1) READ1="$2"; shift 2 ;;
        -2) READ2="$2"; shift 2 ;;
        --assembler) ASSEMBLER="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --min-length) MIN_LENGTH="$2"; shift 2 ;;
        --kmer-sizes) KMER_SIZES="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) echo "Unexpected argument: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$READ1" ]]; then
    echo "Error: -1 READ1 is required." >&2
    usage 1
fi

if [[ "$ASSEMBLER" != "megahit" && "$ASSEMBLER" != "metaspades" ]]; then
    echo "Error: --assembler must be 'megahit' or 'metaspades'." >&2
    exit 1
fi

mkdir -p "$OUTDIR"

SAMPLE=$(basename "$READ1" | sed -E 's/(_R1)?(_001)?(_hostdepleted)?\.(fastq|fq)(\.gz)?$//')
MEMORY_BYTES=$(( MEMORY * 1073741824 ))

PE_MODE=false
if [[ -n "$READ2" ]]; then
    PE_MODE=true
fi

# Step 1: Run assembler
if [[ "$ASSEMBLER" == "megahit" ]]; then
    echo "==> Running MEGAHIT assembly..."
    MEGAHIT_DIR="$OUTDIR/megahit_out"

    # MEGAHIT refuses to overwrite; remove previous output if exists
    if [[ -d "$MEGAHIT_DIR" ]]; then
        rm -rf "$MEGAHIT_DIR"
    fi

    MEGAHIT_ARGS=(
        --min-contig-len "$MIN_LENGTH"
        --num-cpu-threads "$THREADS"
        -m "$MEMORY_BYTES"
        -o "$MEGAHIT_DIR"
    )

    if $PE_MODE; then
        MEGAHIT_ARGS+=(-1 "$READ1" -2 "$READ2")
    else
        MEGAHIT_ARGS+=(-r "$READ1")
    fi

    megahit "${MEGAHIT_ARGS[@]}"

    RAW_CONTIGS="$MEGAHIT_DIR/final.contigs.fa"

elif [[ "$ASSEMBLER" == "metaspades" ]]; then
    echo "==> Running metaSPAdes assembly..."
    SPADES_DIR="$OUTDIR/metaspades_out"

    SPADES_ARGS=(
        --meta
        -t "$THREADS"
        -m "$MEMORY"
        -o "$SPADES_DIR"
    )

    if [[ -n "$KMER_SIZES" ]]; then
        SPADES_ARGS+=(-k "$KMER_SIZES")
    fi

    if $PE_MODE; then
        SPADES_ARGS+=(-1 "$READ1" -2 "$READ2")
    else
        SPADES_ARGS+=(-s "$READ1")
    fi

    spades.py "${SPADES_ARGS[@]}"

    RAW_CONTIGS="$SPADES_DIR/contigs.fasta"
fi

# Step 2: Filter contigs by minimum length
echo "==> Filtering contigs >= ${MIN_LENGTH} bp..."
FILTERED_CONTIGS="$OUTDIR/contigs_min${MIN_LENGTH}bp.fasta"

awk -v min="$MIN_LENGTH" '
/^>/ {
    if (NR > 1 && length(seq) >= min) {
        printf "%s\n%s\n", header, seq
    }
    header = $0
    seq = ""
    next
}
{
    seq = seq $0
}
END {
    if (length(seq) >= min) {
        printf "%s\n%s\n", header, seq
    }
}
' "$RAW_CONTIGS" > "$FILTERED_CONTIGS"

# Step 3: Compute assembly statistics
echo "==> Computing assembly statistics..."
STATS_FILE="$OUTDIR/assembly_stats.txt"

awk -v assembler="$ASSEMBLER" '
BEGIN {
    n = 0; total_len = 0; max_len = 0; gc = 0
}
/^>/ {
    if (n > 0 && length(seq) > 0) {
        len = length(seq)
        lengths[n] = len
        total_len += len
        if (len > max_len) max_len = len
        for (i = 1; i <= len; i++) {
            c = substr(seq, i, 1)
            if (c == "G" || c == "C" || c == "g" || c == "c") gc++
        }
    }
    n++
    seq = ""
    next
}
{
    seq = seq $0
}
END {
    if (n > 0 && length(seq) > 0) {
        len = length(seq)
        lengths[n] = len
        total_len += len
        if (len > max_len) max_len = len
        for (i = 1; i <= len; i++) {
            c = substr(seq, i, 1)
            if (c == "G" || c == "C" || c == "g" || c == "c") gc++
        }
    }

    # Sort lengths descending for N50/L50
    for (i = 1; i <= n; i++) {
        for (j = i + 1; j <= n; j++) {
            if (lengths[j] > lengths[i]) {
                tmp = lengths[i]
                lengths[i] = lengths[j]
                lengths[j] = tmp
            }
        }
    }

    # Calculate N50 and L50
    cumsum = 0
    half = total_len / 2
    n50 = 0; l50 = 0
    for (i = 1; i <= n; i++) {
        cumsum += lengths[i]
        if (cumsum >= half && n50 == 0) {
            n50 = lengths[i]
            l50 = i
        }
    }

    gc_pct = (total_len > 0) ? (gc / total_len) * 100 : 0

    printf "Assembly Statistics\n"
    printf "===================\n"
    printf "Assembler:       %s\n", assembler
    printf "Total contigs:   %d\n", n
    printf "Total length:    %d bp\n", total_len
    printf "Largest contig:  %d bp\n", max_len
    printf "N50:             %d bp\n", n50
    printf "L50:             %d\n", l50
    printf "GC content:      %.2f%%\n", gc_pct
}
' "$FILTERED_CONTIGS" > "$STATS_FILE"

echo "==> Assembly complete."
cat "$STATS_FILE"
echo ""
echo "==> Output files:"
echo "  Contigs: $FILTERED_CONTIGS"
echo "  Stats:   $STATS_FILE"
