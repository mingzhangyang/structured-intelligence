# Variant Filtering Reference: GATK Hard Filters & VQSR

## Hard Filters — GATK Best Practice Thresholds

Use hard filters when VQSR is not applicable (small cohorts, targeted panels, <30 WES samples).

### SNP hard filters

```bash
gatk VariantFiltration \
  -R ref.fa \
  -V cohort.vcf.gz \
  -O cohort.snp_filtered.vcf.gz \
  --select-type-to-include SNP \
  --filter-expression "QD < 2.0"          --filter-name "QD2" \
  --filter-expression "FS > 60.0"          --filter-name "FS60" \
  --filter-expression "MQ < 40.0"          --filter-name "MQ40" \
  --filter-expression "MQRankSum < -12.5"  --filter-name "MQRankSum-12.5" \
  --filter-expression "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8" \
  --filter-expression "SOR > 3.0"          --filter-name "SOR3"
```

### Indel hard filters

```bash
gatk VariantFiltration \
  -R ref.fa \
  -V cohort.vcf.gz \
  -O cohort.indel_filtered.vcf.gz \
  --select-type-to-include INDEL \
  --filter-expression "QD < 2.0"              --filter-name "QD2" \
  --filter-expression "FS > 200.0"            --filter-name "FS200" \
  --filter-expression "ReadPosRankSum < -20.0" --filter-name "ReadPosRankSum-20" \
  --filter-expression "SOR > 10.0"            --filter-name "SOR10"
```

### Annotation meanings

| Annotation | Meaning | Failure indicates |
|------------|---------|------------------|
| `QD` | Quality by Depth: QUAL / DP | Low-confidence calls relative to coverage |
| `FS` | Fisher Strand bias (Phred) | Strong strand bias in supporting reads |
| `MQ` | Root mean square mapping quality | Reads supporting variant have poor alignment |
| `MQRankSum` | Mann-Whitney test: MQ of alt vs ref reads | Alt reads map worse than ref reads |
| `ReadPosRankSum` | Position of variant in reads | Variant consistently near read ends |
| `SOR` | Symmetric Odds Ratio of strand bias | More sensitive strand bias metric than FS |

## VQSR — Prerequisites

VQSR builds a Gaussian mixture model on a truth/training set; it requires enough variants to estimate the model. Minimum requirements:

- **WGS**: ≥1 sample (typically ≥30 variants per annotation dimension is sufficient)
- **WES**: ≥30 samples; single WES samples should use hard filters

### Resource VCFs (GRCh38)

| Resource | Truth | Training | Prior | Use |
|----------|-------|----------|-------|-----|
| HapMap 3.3 | true | true | 15 | High-confidence SNPs |
| Omni 2.5 | false | true | 12 | Array-derived SNP set |
| 1000G phase1 high confidence SNPs | false | true | 10 | Broad SNP training |
| dbSNP | false | false | 2 | Known sites for sensitivity |

### VQSR annotation features

SNPs: `QD`, `FS`, `SOR`, `MQ`, `MQRankSum`, `ReadPosRankSum`
Indels: `QD`, `FS`, `SOR`, `MQRankSum`, `ReadPosRankSum` (drop MQ for indels)

### Running VQSR

```bash
# Step 1: Build SNP recalibration model
gatk VariantRecalibrator \
  -V cohort.vcf.gz \
  --resource:hapmap,known=false,training=true,truth=true,prior=15 hapmap.vcf.gz \
  --resource:omni,known=false,training=true,truth=false,prior=12 omni.vcf.gz \
  --resource:1000G,known=false,training=true,truth=false,prior=10 1000G_phase1.vcf.gz \
  --resource:dbsnp,known=true,training=false,truth=false,prior=2 dbsnp.vcf.gz \
  -an QD -an FS -an SOR -an MQ -an MQRankSum -an ReadPosRankSum \
  -mode SNP \
  -O cohort.snp.recal \
  --tranches-file cohort.snp.tranches

# Step 2: Apply SNP recalibration
gatk ApplyVQSR \
  -V cohort.vcf.gz \
  --recal-file cohort.snp.recal \
  --tranches-file cohort.snp.tranches \
  --truth-sensitivity-filter-level 99.5 \
  -mode SNP \
  -O cohort.snp_vqsr.vcf.gz
```

### Truth sensitivity thresholds

| Threshold | Trade-off |
|-----------|-----------|
| 99.5% SNPs | High sensitivity; retains more false positives (recommended default) |
| 99.0% SNPs | More stringent; better specificity for clinical applications |
| 99.0% Indels | Standard; indel recalibration is less reliable than SNP |
| 95.0% Indels | Very stringent; use only if downstream false positive tolerance is low |

Lower percentage = more stringent filter = fewer variants pass.

## bcftools filter — Soft vs Hard Filtering

```bash
# Soft filter: adds FILTER tag, record retained
bcftools filter \
  -e 'QUAL<20 || DP<10' \
  --soft-filter LowQual \
  -O z -o filtered.vcf.gz input.vcf.gz

# Hard filter: removes non-PASS records
bcftools view \
  -f PASS \
  -O z -o pass_only.vcf.gz filtered.vcf.gz
```

The `-e` expression syntax supports: `||`, `&&`, `INFO/DP`, `FORMAT/GQ`, `QUAL`, `FILTER`. Use `bcftools filter --list-tags` on a VCF to see available fields.

## Common Gotchas

- **VQSR fails with too few variants.** A Gaussian mixture model needs sufficient data density. If VariantRecalibrator exits with "no data found in gaussian" errors, fall back to hard filters.
- **Resource VCF genome build must exactly match sample VCF.** A GRCh37 resource against a GRCh38 cohort VCF will yield zero training variants without a useful error message. Verify with `bcftools stats` on the resource VCFs.
- **Soft-filter preserves all records; hard-filter removes them.** `bcftools filter -e` + `--soft-filter` sets the FILTER field but keeps the variant line. To remove it, pipe through `bcftools view -f PASS` or use `VariantFiltration` then `SelectVariants --exclude-filtered`.
- **VariantFiltration --filter-expression uses JEXL syntax.** Use `&&` and `||`; single `&` and `|` are bitwise operators and will silently misbehave.
- **MQ annotation is unreliable for indels in VQSR.** The mapping quality metric is less informative at indel sites; omit `-an MQ` when running VQSR in `-mode INDEL`.
