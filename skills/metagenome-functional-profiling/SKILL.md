---
name: metagenome-functional-profiling
description: Functional annotation of metagenomic data using HUMAnN 3 for pathway abundance, Prokka for gene prediction, and eggNOG-mapper for ortholog assignment.
---

# Skill: metagenome-functional-profiling

## Use When

- The user wants to know what metabolic functions are present in a metagenome.
- The user needs pathway-level abundance profiles (MetaCyc, KEGG).
- The user wants to annotate predicted genes from MAGs or assembled contigs.
- The user needs gene family and ortholog group assignments.

## Inputs

- Required:
  - Host-depleted FASTQ file(s) for HUMAnN, OR assembled contigs/MAGs FASTA for Prokka/eggNOG.
- Optional:
  - `--tool STR` — Tool to use: `humann`, `prokka`, or `eggnog` (default: `humann`).
  - `--db PATH` — HUMAnN databases (ChocoPhlAn, UniRef) or eggNOG database path.
  - `--taxonomic-profile FILE` — Taxonomic profile from `metagenome-taxonomic-profiling` to speed up HUMAnN.
  - `--kingdom STR` — Prokka kingdom (default: `Bacteria`).
  - `--threads N` — Number of threads (default: 4).
  - `--outdir DIR` — Output directory (default: `functional_profiling_results`).

## Workflow

1. If HUMAnN: run `humann` with `--input` FASTQs, optionally with `--taxonomic-profile` for guided search.
2. HUMAnN produces: gene families (RPK), pathway abundance, pathway coverage.
3. Normalize HUMAnN output with `humann_renorm_table` (CPM or relative abundance).
4. If Prokka: run on contigs/MAGs for gene prediction and annotation.
5. If eggNOG-mapper: run `emapper.py` on predicted protein sequences for COG/KEGG/GO annotation.
6. Report: number of gene families, pathways detected, top abundant pathways, functional category distribution.

## Output Contract

- **HUMAnN gene family table** — Gene families with RPK values (`<outdir>/<sample>_genefamilies.tsv`).
- **HUMAnN pathway abundance table** — Pathway abundances (`<outdir>/<sample>_pathabundance.tsv`).
- **HUMAnN pathway coverage table** — Pathway coverage scores (`<outdir>/<sample>_pathcoverage.tsv`).
- **Prokka annotations** — GFF, GBK, FAA, FFN files (`<outdir>/prokka/`).
- **eggNOG annotation table** — COG, KEGG, GO annotations (`<outdir>/eggnog/<sample>.emapper.annotations`).
- **Functional summary** — Top pathways, gene family counts, functional category distribution (`<outdir>/functional_summary.txt`).

## Limits

- HUMAnN 3 requires ChocoPhlAn (approximately 15 GB) and UniRef90 (approximately 20 GB) databases.
- Prokka is designed for prokaryotic genomes; use appropriate `--kingdom` for archaea.
- eggNOG database is approximately 45 GB.
- HUMAnN is computationally intensive and may take hours per sample; for large cohorts, consider running on HPC.
- HUMAnN, Prokka, and eggNOG-mapper must be installed and available on `$PATH`.
- Prokka and eggNOG-mapper operate on contigs/proteins, not raw reads.
- Common failure cases:
  - HUMAnN ChocoPhlAn or UniRef databases not downloaded or path misconfigured.
  - Prokka failing on non-prokaryotic contigs when `--kingdom` is set incorrectly.
  - eggNOG-mapper database version mismatch with the installed emapper version.
