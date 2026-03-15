# Variant Calling Reference: GATK HaplotypeCaller & DeepVariant

## GATK HaplotypeCaller — Single-Sample VCF Mode

```bash
gatk HaplotypeCaller \
  -R ref.fa \
  -I sample.markdup.bam \
  -O sample.vcf.gz \
  -L targets.bed \                    # WES only; omit for WGS
  --sample-ploidy 2 \                 # default; change for sex chromosomes or polyploid
  --native-pair-hmm-threads 4
```

### Key flags

| Flag | Meaning |
|------|---------|
| `-R` | Reference FASTA (must have `.fai` and `.dict`) |
| `-I` | Input BAM/CRAM (must have read groups and index) |
| `-O` | Output VCF or gVCF |
| `-L` | Restrict calling to intervals (BED or interval list) |
| `--emit-ref-confidence GVCF` | Emit per-base reference blocks; enables joint calling workflow |
| `--sample-ploidy` | Ploidy assumption (default 2) |
| `--native-pair-hmm-threads` | Threads for the pair-HMM calculation (CPU-bound bottleneck) |
| `--java-options "-Xmx8G"` | JVM heap size; increase for large BAMs or many intervals |

## GATK GVCF Workflow (Multi-Sample)

```
Per-sample:
  HaplotypeCaller --emit-ref-confidence GVCF → sample.g.vcf.gz

Joint:
  GenomicsDBImport → genomicsdb workspace
  GenotypeGVCFs   → cohort.vcf.gz
```

GenomicsDBImport consolidates gVCFs per genomic interval into a database. GenotypeGVCFs then performs joint genotyping across all samples. Note that GenotypeGVCFs is a separate downstream step not performed within this skill.

```bash
# GenomicsDBImport (one interval at a time for scalability)
gatk GenomicsDBImport \
  -V sample1.g.vcf.gz \
  -V sample2.g.vcf.gz \
  --genomicsdb-workspace-path genomicsdb/chr1 \
  -L chr1
```

## DeepVariant

### Docker command pattern

```bash
docker run \
  -v /data:/data \
  google/deepvariant:latest \
  /opt/deepvariant/bin/run_deepvariant \
    --model_type WGS \
    --ref /data/ref.fa \
    --reads /data/sample.markdup.bam \
    --output_vcf /data/sample.deepvariant.vcf.gz \
    --output_gvcf /data/sample.deepvariant.g.vcf.gz \
    --regions chr1:1-50000000 \
    --num_shards 16
```

### Model types

| Model | Use case |
|-------|---------|
| `WGS` | Illumina whole-genome sequencing |
| `WES` | Illumina whole-exome sequencing |
| `PACBIO` | PacBio HiFi long reads |
| `ONT_R104` | Oxford Nanopore (R10.4+ chemistry) |
| `HYBRID_PACBIO_ILLUMINA` | Hybrid assembly reads |

### Key DeepVariant flags

| Flag | Meaning |
|------|---------|
| `--regions` | Restrict calling to BED or interval string (e.g., `chr1:1-248956422`) |
| `--num_shards` | Parallelism for make_examples step; set to available CPU cores |
| `--output_gvcf` | Emit gVCF in addition to VCF |

## bcftools index

```bash
bcftools index --tbi sample.vcf.gz     # tabix index (.tbi); required for most downstream tools
bcftools index sample.vcf.gz           # CSI index (.csi); supports chromosomes > 2^29 bp
```

Use `--tbi` for broad compatibility. CSI is needed for genomes with very large chromosomes (e.g., some plant genomes).

## Ti/Tv Ratio — Variant Quality Check

Transition/transversion ratio is a proxy for false positive rate:

| Data type | Expected Ti/Tv |
|-----------|---------------|
| WGS SNPs | 2.0–2.1 |
| WES SNPs | 2.8–3.3 |
| Random mutations | ~0.5 |

A ratio significantly below the expected range indicates excess false positives (transversions). Calculate with:

```bash
bcftools stats sample.vcf.gz | grep "Ts/Tv"
```

## Common Gotchas

- **BAM must have read groups.** GATK checks for RG tags; missing groups cause an immediate failure with `SAM/BAM file ... is missing the read group field`.
- **Reference must have both `.fai` and `.dict`.** Generate with `samtools faidx ref.fa` and `picard CreateSequenceDictionary -R ref.fa`.
- **Increase Java heap for large jobs.** Pass `--java-options "-Xmx16G"` before the tool name. Default heap is often insufficient for genome-wide calling.
- **GVCF output requires a separate joint-calling step.** A `.g.vcf.gz` is not a valid final VCF; it must pass through GenomicsDBImport and GenotypeGVCFs.
- **DeepVariant model type must match the data type.** Using WGS model on WES data degrades accuracy — use `WES` model and provide `--regions` matching the capture BED.
- **`-L` intervals must use the same chromosome naming as the reference.** A BED with `chr1` against a non-chr reference produces zero output without error.
