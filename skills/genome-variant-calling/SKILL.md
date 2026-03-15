---
name: genome-variant-calling
description: Call SNVs and indels from aligned BAMs using GATK HaplotypeCaller or DeepVariant with optional GVCF output for joint genotyping.
---

# Skill: genome-variant-calling

## Use When

- User wants to call germline variants (SNPs, indels) from a deduplicated BAM.
- User needs to produce a VCF or GVCF for downstream joint genotyping.
- User wants to compare variant callers (GATK HaplotypeCaller vs DeepVariant).
- User is performing WGS or WES variant discovery.

## Inputs

- Required:
  - Deduplicated BAM file with index (`.bam` + `.bai`).
  - Reference FASTA with `.fai` index and `.dict` sequence dictionary.
- Optional:
  - Caller choice: `gatk` or `deepvariant` (default: `gatk`).
  - Intervals or BED file (for WES target regions).
  - GVCF mode flag (emit reference confidence; default: off).
  - Ploidy (default: 2).
  - Output directory (default: current directory).
  - Threads / memory allocation.

## Workflow

1. Validate that the BAM is sorted, indexed, and has read groups.
2. If GATK: run `gatk HaplotypeCaller` with `--emit-ref-confidence GVCF` (if GVCF mode) or standard VCF output.
3. If DeepVariant: run via Docker or Singularity with the appropriate model type (`WGS` or `WES`).
4. If intervals are provided (WES): restrict variant calling to target regions with padding.
5. Index the output VCF/GVCF with `bcftools index` or `gatk IndexFeatureFile`.
6. Report variant counts: total variants, SNPs, indels, het/hom ratio, Ti/Tv ratio.

## Output Contract

- VCF or gVCF file (`.vcf.gz`).
- VCF index (`.vcf.gz.tbi`).
- Variant summary statistics (total, SNPs, indels, het/hom ratio, Ti/Tv).

## Limits

- GATK requires Java 17+.
- DeepVariant requires Docker or Singularity (GPU recommended for performance).
- Joint genotyping (GenomicsDBImport + GenotypeGVCFs) is a separate downstream step.
- Memory: ~4 GB per thread for GATK HaplotypeCaller; GPU recommended for DeepVariant.
- This skill handles single-sample calling; multi-sample joint calling is out of scope.
- Common failure cases:
  - BAM missing read groups, causing GATK HaplotypeCaller to reject the input.
  - Reference FASTA lacking `.dict` or `.fai` index files.
  - DeepVariant Docker/Singularity image not found or GPU driver mismatch.
