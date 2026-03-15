---
name: genome-variant-annotation
description: Annotate variants with functional effects using SnpEff or Ensembl VEP, adding gene impact, population frequencies, and clinical significance.
---

# Skill: genome-variant-annotation

## Use When

- User wants to annotate variants with gene and transcript impact predictions.
- User needs to predict functional consequences (missense, nonsense, splice-site, etc.).
- User wants to add population allele frequencies (gnomAD, 1000 Genomes).
- User wants to add clinical annotations (ClinVar significance).
- User needs to compare annotation engines (SnpEff vs VEP).

## Inputs

- Required:
  - Filtered VCF file (`.vcf.gz`).
- Optional:
  - Annotator choice: `snpeff` or `vep` (default: `snpeff`).
  - Genome build (default: `GRCh38`).
  - Cache directory for annotation databases.
  - Additional VEP plugins or fields (e.g., CADD, LOFTEE).
  - Output format (default: VCF).

## Workflow

1. If SnpEff: run `snpEff ann` with the appropriate database (e.g., `GRCh38.105`), producing an annotated VCF and summary stats HTML.
2. If VEP: run `vep` with `--cache`, `--merged` or `--refseq`, and add plugins (CADD, gnomAD, ClinVar, LOFTEE).
3. Add fields to each variant: gene symbol, consequence, impact tier (HIGH / MODERATE / LOW / MODIFIER), HGVS notation.
4. Optionally add population allele frequencies from gnomAD.
5. Generate summary statistics: variants by impact category, genes with HIGH-impact variants.

## Output Contract

- Annotated VCF file (`.vcf.gz`).
- Annotation summary: HTML report (SnpEff) or stats file (VEP).
- Variant impact distribution (HIGH, MODERATE, LOW, MODIFIER counts).

## Limits

- SnpEff and VEP annotation databases must be pre-downloaded to the cache directory.
- VEP plugins (CADD, LOFTEE, gnomAD) require separate data file downloads.
- Annotation databases must match the reference genome build (GRCh37 vs GRCh38).
- VEP is generally slower but more configurable than SnpEff.
- Large VCFs (millions of variants) may require significant memory and runtime.
- Common failure cases:
  - SnpEff database name not matching the reference build (e.g., using `hg19` when VCF is on `GRCh38`).
  - VEP cache directory missing or not matching the installed VEP version.
  - VEP plugin data files (CADD, LOFTEE) not downloaded or path misconfigured.
