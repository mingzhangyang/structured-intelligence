#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <ACCESSION|FILE> [OPTIONS]

Download SRA data as FASTQ using prefetch + fasterq-dump.

Arguments:
  ACCESSION      Single SRR/SRX/SRS/SRP/PRJNA accession
  FILE           Path to plain-text file with one accession per line

Options:
  --outdir DIR       Output directory (default: sra_downloads)
  --threads N        Threads for fasterq-dump (default: 6)
  --temp-dir DIR     Temp directory for fasterq-dump (default: system temp)
  --split-3          Split paired-end into R1/R2 + unpaired (default)
  --split-files      Split into per-read files instead of split-3
  --no-gzip          Do not gzip output FASTQ files
  --original-sra     Keep .sra cache file after FASTQ conversion
  --skip-prefetch    Run fasterq-dump directly (no .sra intermediate)
  --no-verify        Skip vdb-validate after prefetch
  --min-spots N      Skip runs with fewer than N spots (default: 0)
  -h, --help         Show this help
EOF
    exit "${1:-0}"
}

# ---------- defaults ----------
OUTDIR="sra_downloads"
THREADS=6
TMPDIR_OPT=""
SPLIT_MODE="--split-3"
GZIP=true
KEEP_SRA=false
SKIP_PREFETCH=false
VERIFY=true
MIN_SPOTS=0

# ---------- parse args ----------
INPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir)       OUTDIR="$2";       shift 2 ;;
        --threads)      THREADS="$2";      shift 2 ;;
        --temp-dir)     TMPDIR_OPT="$2";   shift 2 ;;
        --split-3)      SPLIT_MODE="--split-3";    shift ;;
        --split-files)  SPLIT_MODE="--split-files"; shift ;;
        --no-gzip)      GZIP=false;        shift ;;
        --original-sra) KEEP_SRA=true;     shift ;;
        --skip-prefetch) SKIP_PREFETCH=true; shift ;;
        --no-verify)    VERIFY=false;      shift ;;
        --min-spots)    MIN_SPOTS="$2";    shift 2 ;;
        -h|--help)      usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *)  INPUT="$1"; shift ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    echo "Error: ACCESSION or FILE is required." >&2
    usage 1
fi

# ---------- resolve accession list ----------
ACCESSIONS=()

is_file=false
if [[ -f "$INPUT" ]]; then
    is_file=true
fi

if $is_file; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//[$'\r\n']/}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        ACCESSIONS+=("$line")
    done < "$INPUT"
else
    ACC="$INPUT"
    # Expand non-SRR accessions to SRR list via E-utilities
    if [[ "$ACC" =~ ^(SRP|SRS|SRX|PRJNA|PRJEB|DRP)[0-9]+ ]]; then
        echo "==> Expanding $ACC to SRR accessions via E-utilities..."
        mapfile -t ACCESSIONS < <(
            esearch -db sra -query "$ACC" | efetch -format runinfo | \
                awk -F',' 'NR>1 && $1~/^[SE]RR/ {print $1}'
        )
        echo "    Found ${#ACCESSIONS[@]} runs."
    else
        ACCESSIONS=("$ACC")
    fi
fi

if [[ ${#ACCESSIONS[@]} -eq 0 ]]; then
    echo "Error: no accessions to download." >&2
    exit 1
fi

# ---------- setup output dirs ----------
SRA_CACHE="$OUTDIR/sra_cache"
LOG_DIR="$OUTDIR/logs"
mkdir -p "$SRA_CACHE" "$LOG_DIR"

MANIFEST="$OUTDIR/manifest.tsv"
echo -e "run\tr1\tr2\tspots\tsize_bytes\tmd5_r1\tmd5_r2" > "$MANIFEST"

FAILED="$OUTDIR/accessions_failed.txt"
> "$FAILED"

TMPDIR_ARGS=()
if [[ -n "$TMPDIR_OPT" ]]; then
    TMPDIR_ARGS=(--temp "$TMPDIR_OPT")
fi

# ---------- download loop ----------
for SRR in "${ACCESSIONS[@]}"; do
    LOG="$LOG_DIR/${SRR}.log"
    echo "==> Processing $SRR ..."

    {
        RUN_DIR="$OUTDIR/$SRR"
        mkdir -p "$RUN_DIR"

        # --- prefetch ---
        if ! $SKIP_PREFETCH; then
            echo "  [prefetch] $SRR"
            prefetch --output-directory "$SRA_CACHE" "$SRR"

            if $VERIFY; then
                echo "  [vdb-validate] $SRR"
                vdb-validate "$SRA_CACHE/$SRR" 2>&1
            fi
        fi

        # --- fasterq-dump ---
        echo "  [fasterq-dump] $SRR"
        FASTERQ_ARGS=(
            $SPLIT_MODE
            --threads "$THREADS"
            --outdir "$RUN_DIR"
            "${TMPDIR_ARGS[@]}"
        )

        if $SKIP_PREFETCH; then
            fasterq-dump "${FASTERQ_ARGS[@]}" "$SRR"
        else
            fasterq-dump "${FASTERQ_ARGS[@]}" "$SRA_CACHE/$SRR"
        fi

        # --- check min spots ---
        if [[ "$MIN_SPOTS" -gt 0 ]]; then
            SPOTS=$(find "$RUN_DIR" -name "*.fastq" | head -1 | \
                xargs -I{} bash -c 'wc -l < "{}"' | awk '{print int($1/4)}')
            if [[ "$SPOTS" -lt "$MIN_SPOTS" ]]; then
                echo "  SKIP: $SRR has $SPOTS spots (< $MIN_SPOTS minimum)"
                rm -rf "$RUN_DIR"
                continue
            fi
        fi

        # --- gzip ---
        if $GZIP; then
            echo "  [gzip] $SRR"
            if command -v pigz &>/dev/null; then
                pigz -p "$THREADS" "$RUN_DIR"/*.fastq
            else
                gzip "$RUN_DIR"/*.fastq
            fi
        fi

        # --- cleanup sra cache ---
        if ! $KEEP_SRA && ! $SKIP_PREFETCH; then
            rm -rf "$SRA_CACHE/$SRR"
        fi

        # --- manifest entry ---
        R1=$(find "$RUN_DIR" -name "${SRR}_1.fastq*" -o -name "${SRR}.fastq*" 2>/dev/null | sort | head -1)
        R2=$(find "$RUN_DIR" -name "${SRR}_2.fastq*" 2>/dev/null | head -1)
        SIZE=$(du -sb "$RUN_DIR" 2>/dev/null | awk '{print $1}')
        MD5_R1=""
        MD5_R2=""
        [[ -n "$R1" ]] && MD5_R1=$(md5sum "$R1" | awk '{print $1}')
        [[ -n "$R2" ]] && MD5_R2=$(md5sum "$R2" | awk '{print $1}')

        echo -e "$SRR\t$R1\t$R2\t\t$SIZE\t$MD5_R1\t$MD5_R2" >> "$MANIFEST"
        echo "  Done: $RUN_DIR"
    } 2>&1 | tee "$LOG" || {
        echo "  FAILED: $SRR" | tee -a "$FAILED"
    }
done

echo ""
echo "==> Download complete."
echo "    Output:   $OUTDIR/"
echo "    Manifest: $MANIFEST"
FAIL_COUNT=$(wc -l < "$FAILED")
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "    Failed ($FAIL_COUNT): $FAILED"
fi
