#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [--manifest FILE | --uuids UUID...] [OPTIONS]

Download files from the NCI GDC using gdc-client.

Options:
  --manifest FILE    Path to a GDC manifest TSV file
  --uuids UUID,...   Comma-separated or space-separated file UUIDs
  --token-file FILE  GDC user token file for controlled-access data
  --outdir DIR       Output directory (default: gdc_downloads)
  --jobs N           Parallel download streams (default: 1)
  --retries N        Retry count on network errors (default: 3)
  --no-verify        Skip MD5 checksum verification
  --dry-run          Print plan without downloading
  -h, --help         Show this help
EOF
    exit "${1:-0}"
}

# ---------- defaults ----------
MANIFEST=""
UUIDS=()
TOKEN_FILE=""
OUTDIR="gdc_downloads"
JOBS=1
RETRIES=3
VERIFY=true
DRY_RUN=false

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest)   MANIFEST="$2";    shift 2 ;;
        --uuids)      IFS=',' read -ra UUIDS <<< "$2"; shift 2 ;;
        --token-file) TOKEN_FILE="$2";  shift 2 ;;
        --outdir)     OUTDIR="$2";      shift 2 ;;
        --jobs)       JOBS="$2";        shift 2 ;;
        --retries)    RETRIES="$2";     shift 2 ;;
        --no-verify)  VERIFY=false;     shift ;;
        --dry-run)    DRY_RUN=true;     shift ;;
        -h|--help)    usage 0 ;;
        *)            echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$MANIFEST" && ${#UUIDS[@]} -eq 0 ]]; then
    echo "Error: --manifest or --uuids is required." >&2
    usage 1
fi

mkdir -p "$OUTDIR"

# ---------- generate manifest from UUIDs ----------
if [[ ${#UUIDS[@]} -gt 0 && -z "$MANIFEST" ]]; then
    MANIFEST="$OUTDIR/manifest.txt"
    echo "==> Fetching manifest for ${#UUIDS[@]} UUIDs..."
    UUID_PARAM=$(IFS=','; echo "${UUIDS[*]}")
    curl -sSf -o "$MANIFEST" \
        "https://api.gdc.cancer.gov/manifest?ids=${UUID_PARAM}"
    echo "    Manifest written to $MANIFEST"
fi

# ---------- validate manifest ----------
if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest file not found: $MANIFEST" >&2
    exit 1
fi

TOTAL=$(tail -n +2 "$MANIFEST" | grep -c . || true)
echo "==> Manifest: $MANIFEST ($TOTAL files)"

# ---------- check access tier ----------
if [[ -z "$TOKEN_FILE" ]]; then
    echo "  Note: no --token-file provided. Controlled-access files will fail."
fi

# ---------- dry-run ----------
if $DRY_RUN; then
    echo "==> [dry-run] Would run:"
    echo "    gdc-client download \\"
    echo "      -m \"$MANIFEST\" \\"
    [[ -n "$TOKEN_FILE" ]] && echo "      -t \"$TOKEN_FILE\" \\"
    echo "      -d \"$OUTDIR\" \\"
    echo "      --n-processes $JOBS \\"
    echo "      --retry-amount $RETRIES"
    exit 0
fi

# ---------- download ----------
echo "==> Starting GDC download (jobs=$JOBS, retries=$RETRIES)..."
GDC_ARGS=(
    -m "$MANIFEST"
    -d "$OUTDIR"
    --n-processes "$JOBS"
    --retry-amount "$RETRIES"
)
[[ -n "$TOKEN_FILE" ]] && GDC_ARGS+=(-t "$TOKEN_FILE")

gdc-client download "${GDC_ARGS[@]}"

# ---------- verify MD5 ----------
REPORT="$OUTDIR/download_report.tsv"
FAILED="$OUTDIR/failed_uuids.txt"
echo -e "uuid\tfilename\texpected_md5\tactual_md5\tsize_bytes\tstatus" > "$REPORT"
> "$FAILED"

if $VERIFY; then
    echo "==> Verifying MD5 checksums..."
    while IFS=$'\t' read -r uuid filename md5 size state; do
        [[ "$uuid" == "id" ]] && continue
        FILEPATH="$OUTDIR/$uuid/$filename"
        if [[ ! -f "$FILEPATH" ]]; then
            echo -e "$uuid\t$filename\t$md5\t\t$size\tMISSING" >> "$REPORT"
            echo "$uuid" >> "$FAILED"
            continue
        fi
        actual_md5=$(md5sum "$FILEPATH" | awk '{print $1}')
        actual_size=$(stat -c%s "$FILEPATH" 2>/dev/null || stat -f%z "$FILEPATH")
        if [[ "$actual_md5" == "$md5" ]]; then
            echo -e "$uuid\t$filename\t$md5\t$actual_md5\t$actual_size\tOK" >> "$REPORT"
        else
            echo -e "$uuid\t$filename\t$md5\t$actual_md5\t$actual_size\tCHECKSUM_FAIL" >> "$REPORT"
            echo "$uuid" >> "$FAILED"
            echo "  CHECKSUM FAIL: $filename" >&2
        fi
    done < "$MANIFEST"
fi

echo ""
echo "==> Download complete."
echo "    Output:  $OUTDIR/"
echo "    Report:  $REPORT"
FAIL_COUNT=$(wc -l < "$FAILED")
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "    Failed ($FAIL_COUNT UUIDs): $FAILED"
fi
