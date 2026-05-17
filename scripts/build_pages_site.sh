#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.site"
SITE_BASE="https://scientifictooling.org/structured-intelligence"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cp "$ROOT_DIR/docs/index.html" "$OUT_DIR/index.html"
cp "$ROOT_DIR/docs/robots.txt" "$OUT_DIR/robots.txt"

# Generate sitemap from on-disk manuscripts so new entries are picked up automatically.
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
  printf '  <url>\n    <loc>%s/</loc>\n    <changefreq>weekly</changefreq>\n    <priority>1.0</priority>\n  </url>\n' "$SITE_BASE"
  printf '  <url>\n    <loc>%s/manuscripts/</loc>\n    <changefreq>monthly</changefreq>\n    <priority>0.8</priority>\n  </url>\n' "$SITE_BASE"
  for manuscript_index in "$ROOT_DIR"/manuscripts/*/index.html; do
    [[ -f "$manuscript_index" ]] || continue
    slug="$(basename "$(dirname "$manuscript_index")")"
    printf '  <url>\n    <loc>%s/manuscripts/%s/</loc>\n    <changefreq>monthly</changefreq>\n    <priority>0.8</priority>\n  </url>\n' "$SITE_BASE" "$slug"
  done
  printf '</urlset>\n'
} > "$OUT_DIR/sitemap.xml"

mkdir -p "$OUT_DIR/assets"
cp -R "$ROOT_DIR/docs/assets/." "$OUT_DIR/assets/"

# Manuscript pages reference ../../logo.svg (relative to manuscripts/<name>/)
cp "$ROOT_DIR/docs/assets/logo.svg" "$OUT_DIR/logo.svg"
cp "$ROOT_DIR/docs/assets/logo.png" "$OUT_DIR/logo.png"

# Manuscript pages fetch article markdown via ../../docs/articles/<name>.md
mkdir -p "$OUT_DIR/docs/articles"
cp -R "$ROOT_DIR/docs/articles/." "$OUT_DIR/docs/articles/"

mkdir -p "$OUT_DIR/manuscripts"
cp -R "$ROOT_DIR/manuscripts/." "$OUT_DIR/manuscripts/"

echo "Built Pages site at $OUT_DIR"
