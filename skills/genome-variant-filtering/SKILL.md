---
name: genome-variant-filtering
description: Filter raw variant calls using GATK VQSR, GATK hard filters, or bcftools expression-based filtering.
---

# Skill: genome-variant-filtering

## Use When

- User wants to filter a raw VCF to remove low-confidence variants.
- User needs to apply GATK best-practice hard filters or VQSR.
- User wants to use custom bcftools filter expressions.
- User needs to separate SNPs from indels for different filter strategies.

## Inputs

- Required:
  - Raw VCF file (`.vcf.gz`).
  - Reference FASTA (for GATK operations).
- Optional:
  - Filter strategy: `vqsr`, `hard`, or `bcftools` (default: `hard`).
  - Resource VCFs for VQSR: HapMap, Omni, 1000 Genomes, dbSNP.
  - Custom filter expressions (for bcftools mode).
  - Truth sensitivity level for VQSR (default: 99.5 for SNPs, 99.0 for indels).

## Workflow

1. If hard-filter: split VCF into SNPs and indels with `gatk SelectVariants`.
2. Apply GATK recommended hard filters:
   - SNPs: `QD < 2.0`, `FS > 60.0`, `MQ < 40.0`, `MQRankSum < -12.5`, `ReadPosRankSum < -8.0`.
   - Indels: `QD < 2.0`, `FS > 200.0`, `ReadPosRankSum < -20.0`.
3. If VQSR: run `gatk VariantRecalibrator` + `gatk ApplyVQSR` for SNPs then indels with resource annotations.
4. If bcftools: apply user-provided filter expressions via `bcftools filter`.
5. Merge filtered SNPs and indels back into a single VCF.
6. Index the output VCF.
7. Report: variants before and after filtering, pass rate, filter category breakdown.

## Output Contract

- Filtered VCF file (`.vcf.gz`).
- Filter summary statistics: total variants, PASS count, filtered count by category.

## Limits

- VQSR requires a sufficiently large call set to train the model (at least ~30 exomes or 1 WGS); use hard filters for small sample sets.
- Resource VCFs must match the reference genome build (e.g., GRCh38).
- GATK is required for VQSR and hard-filter modes; bcftools mode only requires bcftools.
- Hard filters are recommended when VQSR training data is insufficient.
- Common failure cases:
  - VQSR failing due to too few variants in the training set for model convergence.
  - Resource VCFs on a different genome build than the input VCF (e.g., GRCh37 vs GRCh38).
  - bcftools filter expression syntax errors causing silent empty output.
