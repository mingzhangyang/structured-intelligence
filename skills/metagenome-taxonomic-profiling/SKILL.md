---
name: metagenome-taxonomic-profiling
description: Profile microbial community composition from shotgun metagenomic reads using Kraken2/Bracken or MetaPhlAn 4.
---

# Skill: metagenome-taxonomic-profiling

## Use When

- The user wants to determine which organisms are present in a metagenomic sample.
- The user needs taxonomic abundance estimates at species, genus, or phylum level.
- The user wants to compare Kraken2 vs MetaPhlAn profiling approaches.
- The user needs Bracken re-estimation for more accurate species-level abundance from Kraken2 output.

## Inputs

- Required:
  - Host-depleted FASTQ file(s) (`.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`).
- Optional:
  - `--profiler STR` — Profiler to use: `kraken2` or `metaphlan` (default: `kraken2`).
  - `--db PATH` — Kraken2 or MetaPhlAn database path.
  - `--bracken-db PATH` — Bracken database path (for Bracken re-estimation).
  - `--bracken-len N` — Read length for Bracken (e.g., 100, 150, 250).
  - `--level CHAR` — Taxonomic level for Bracken: `S` (species), `G` (genus), `P` (phylum), etc. (default: `S`).
  - `--threads N` — Number of threads (default: 4).
  - `--outdir DIR` — Output directory (default: `taxonomic_profiling_results`).
  - `--confidence FLOAT` — Kraken2 confidence threshold (default: `0.0`).

## Workflow

1. If Kraken2: run `kraken2` with `--report` to generate a Kraken-style taxonomic report.
2. If Bracken: run `bracken` on the Kraken2 report for abundance re-estimation at the specified taxonomic level.
3. If MetaPhlAn: run `metaphlan` with `--input_type fastq` to produce a merged abundance table.
4. Parse reports: extract top N taxa, relative abundances, and compute diversity metrics (Shannon, Simpson).
5. Report: classification rate, top taxa, total species detected, alpha diversity estimates.

## Output Contract

- **Kraken2 report** — Standard Kraken2 taxonomic report (`<outdir>/<sample>_kraken2_report.txt`).
- **Bracken abundance table** — Re-estimated abundances at the specified level (`<outdir>/<sample>_bracken.txt`), if Bracken is used.
- **MetaPhlAn profile** — Relative abundance table (`<outdir>/<sample>_metaphlan_profile.txt`), if MetaPhlAn is used.
- **Classification rate** — Percentage of reads assigned to a taxon.
- **Top taxa summary** — Top 20 taxa by relative abundance.
- **Diversity metrics** — Shannon and Simpson alpha diversity indices.

## Limits

- Kraken2 standard database is approximately 70 GB and requires sufficient RAM to load into memory.
- MetaPhlAn 4 uses marker genes; it has a smaller database and higher species-level precision but may miss novel taxa without markers.
- Bracken requires a pre-built Bracken database matching the Kraken2 database and the read length used in sequencing.
- Kraken2 and MetaPhlAn must be installed and available on `$PATH`.
- Classification rates vary significantly by database completeness and sample type.
- For low-biomass samples, consider using a higher Kraken2 confidence threshold to reduce false positives.
- Common failure cases:
  - Kraken2 database too large to fit in available RAM, causing out-of-memory crash.
  - Bracken database read length not matching actual sequencing read length.
  - MetaPhlAn marker database version incompatible with the installed MetaPhlAn version.
