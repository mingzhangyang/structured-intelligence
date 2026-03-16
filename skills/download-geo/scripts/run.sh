#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <GSE_ACCESSION> [OPTIONS]

Download supplementary files, series matrix, or SRA accession list from NCBI GEO.

Arguments:
  GSE_ACCESSION   GEO series accession (e.g., GSE12345)

Options:
  --type TYPE        What to download: supplementary (default), matrix, both, sra-list
  --outdir DIR       Output directory (default: geo_downloads)
  --filter PATTERN   Glob pattern to select supplementary files (e.g. "*_counts.txt.gz")
  --soft             Also download the full SOFT metadata file
  --no-decompress    Do not auto-decompress downloaded files
  --dry-run          List files without downloading
  -h, --help         Show this help
EOF
    exit "${1:-0}"
}

# ---------- defaults ----------
ACC=""
TYPE="supplementary"
OUTDIR="geo_downloads"
FILTER="*"
SOFT=false
DRY_RUN=false
# DECOMPRESS is recorded but not used to auto-decompress in this script
# (files are left as-is; user can run gunzip separately)

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)          TYPE="$2";    shift 2 ;;
        --outdir)        OUTDIR="$2";  shift 2 ;;
        --filter)        FILTER="$2";  shift 2 ;;
        --soft)          SOFT=true;    shift ;;
        --no-decompress) shift ;;  # default behavior; flag accepted for compatibility
        --dry-run)       DRY_RUN=true; shift ;;
        -h|--help)       usage 0 ;;
        -*)              echo "Unknown option: $1" >&2; usage 1 ;;
        *)               ACC="$1"; shift ;;
    esac
done

if [[ -z "$ACC" ]]; then
    echo "Error: GSE_ACCESSION is required." >&2
    usage 1
fi

# ---------- compute FTP prefix ----------
# GSE1-GSE999 → GSEnnn, GSE1000-GSE9999 → GSE1nnn, etc.
# Rule: replace last 3 digits with "nnn"
NUMERIC="${ACC#GSE}"
if [[ ${#NUMERIC} -le 3 ]]; then
    PREFIX="GSEnnn"
else
    PREFIX="GSE${NUMERIC:0:$(( ${#NUMERIC} - 3 ))}nnn"
fi

BASE_FTP="https://ftp.ncbi.nlm.nih.gov/geo/series/${PREFIX}/${ACC}"
SUPPL_URL="${BASE_FTP}/suppl/"
MATRIX_URL="${BASE_FTP}/matrix/"
SOFT_URL="${BASE_FTP}/soft/"

echo "==> GEO accession : $ACC"
echo "    FTP base       : $BASE_FTP"
echo "    Download type  : $TYPE"

# ---------- helper: wget download ----------
geo_wget() {
    local url="$1"
    local dest="$2"
    mkdir -p "$dest"
    wget -q -r -nH --cut-dirs=99 -np -nd \
        --accept="$FILTER" \
        -P "$dest" \
        "$url" 2>&1 || true
}

# ---------- dry-run: list files ----------
if $DRY_RUN; then
    echo "==> [dry-run] Files available:"
    if [[ "$TYPE" == "supplementary" || "$TYPE" == "both" ]]; then
        echo "  Supplementary ($SUPPL_URL):"
        curl -s "$SUPPL_URL" | grep -oP '(?<=href=")[^"]+' | grep -v '^\.\.' || echo "    (none or unavailable)"
    fi
    if [[ "$TYPE" == "matrix" || "$TYPE" == "both" ]]; then
        echo "  Matrix ($MATRIX_URL):"
        curl -s "$MATRIX_URL" | grep -oP '(?<=href=")[^"]+' | grep -v '^\.\.' || echo "    (none or unavailable)"
    fi
    if $SOFT; then
        echo "  SOFT ($SOFT_URL):"
        curl -s "$SOFT_URL" | grep -oP '(?<=href=")[^"]+' | grep -v '^\.\.' || echo "    (none or unavailable)"
    fi
    exit 0
fi

# ---------- download ----------
MANIFEST="$OUTDIR/download_manifest.tsv"
echo -e "accession\tfile\turl\tlocal_path" > "$MANIFEST"

if [[ "$TYPE" == "supplementary" || "$TYPE" == "both" ]]; then
    DEST="$OUTDIR/$ACC/supplementary"
    echo "==> Downloading supplementary files to $DEST ..."
    geo_wget "$SUPPL_URL" "$DEST"
    find "$DEST" -type f | while read -r f; do
        fname=$(basename "$f")
        echo -e "$ACC\t$fname\t${SUPPL_URL}${fname}\t$f" >> "$MANIFEST"
    done
fi

if [[ "$TYPE" == "matrix" || "$TYPE" == "both" ]]; then
    DEST="$OUTDIR/$ACC/matrix"
    echo "==> Downloading series matrix to $DEST ..."
    geo_wget "$MATRIX_URL" "$DEST"
    find "$DEST" -type f | while read -r f; do
        fname=$(basename "$f")
        echo -e "$ACC\t$fname\t${MATRIX_URL}${fname}\t$f" >> "$MANIFEST"
    done
fi

if $SOFT; then
    DEST="$OUTDIR/$ACC/soft"
    echo "==> Downloading SOFT file to $DEST ..."
    geo_wget "$SOFT_URL" "$DEST"
    find "$DEST" -type f | while read -r f; do
        fname=$(basename "$f")
        echo -e "$ACC\t$fname\t${SOFT_URL}${fname}\t$f" >> "$MANIFEST"
    done
fi

# ---------- sra-list mode ----------
if [[ "$TYPE" == "sra-list" ]]; then
    SRA_LIST="$OUTDIR/$ACC/sra_accessions.txt"
    mkdir -p "$OUTDIR/$ACC"
    echo "==> Fetching SRA run accessions for $ACC ..."
    esearch -db gds -query "${ACC}[Accession]" | elink -target sra | \
        efetch -format runinfo | awk -F',' 'NR>1 && $1~/^[SE]RR/ {print $1}' \
        > "$SRA_LIST"
    COUNT=$(wc -l < "$SRA_LIST")
    echo "    Found $COUNT SRR accessions → $SRA_LIST"
    echo ""
    echo "    To download raw FASTQ, run:"
    echo "      download-sra $SRA_LIST --outdir ${OUTDIR}/${ACC}/fastq"
fi

echo ""
echo "==> Done."
echo "    Manifest: $MANIFEST"
