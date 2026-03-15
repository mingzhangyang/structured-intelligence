---
name: genomics-quality-thresholds
description: Platform-specific QC criteria and pass/fail thresholds for NGS data across Illumina, ONT, and PacBio platforms.
---

# Quality Thresholds

## Illumina Short-Read Sequencing

### Raw Read QC (FastQC)

| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Per-base quality | Median ≥ 28 all positions | Median < 28 any position | Median < 20 any position |
| Mean sequence quality | Mean ≥ 27 | Mean 20–27 | Mean < 20 |
| Adapter content | < 5% at any position | 5–10% | > 10% |
| Sequence duplication | < 20% total | 20–50% | > 50% (unless amplicon) |
| GC content | Normal distribution matching theoretical | Shifted or bimodal | — |
| N content | < 5% at any position | 5–20% | > 20% |

### Post-Trimming Targets (fastp)

- Reads surviving: ≥ 85% of input.
- Mean quality after trimming: ≥ Q30.
- Adapter removal rate: > 95% of detected adapters removed.

### Alignment QC

| Metric | WGS Target | WES Target |
|--------|-----------|-----------|
| Mapping rate | ≥ 95% | ≥ 95% |
| Properly paired | ≥ 90% | ≥ 90% |
| Duplicate rate | < 15% | < 20% |
| Mean coverage | ≥ 30× (germline), ≥ 60× (somatic) | ≥ 50× on-target |
| On-target rate | N/A | ≥ 70% |
| Coverage uniformity (≥20×) | ≥ 90% of genome | ≥ 90% of target |
| Insert size | 300–500 bp (PE150) | 150–250 bp typical |

### Variant Calling QC

| Metric | Typical Range |
|--------|--------------|
| Ti/Tv ratio (WGS, SNPs) | 2.0–2.1 |
| Ti/Tv ratio (WES, SNPs) | 2.8–3.3 |
| Het/Hom ratio | 1.5–2.0 (outbred diploid) |
| SNPs per genome (WGS) | 4.0–5.0 million |
| Indels per genome (WGS) | 0.5–0.7 million |
| DbSNP overlap | ≥ 99% for SNPs |

## Oxford Nanopore (ONT)

| Metric | Target |
|--------|--------|
| Mean read quality | ≥ Q10 (R9.4), ≥ Q20 (R10.4/duplex) |
| N50 read length | Application-dependent |
| Mapping rate | ≥ 90% |
| Per-read accuracy | ≥ 95% (simplex), ≥ 99% (duplex) |

## PacBio HiFi

| Metric | Target |
|--------|--------|
| Mean read quality | ≥ Q20 (HiFi) |
| Mean read length | 10–25 kb |
| Mapping rate | ≥ 95% |
| Per-read accuracy | ≥ 99.5% |

## RNA-seq QC

| Metric | Target |
|--------|--------|
| Mapping rate | ≥ 70% (STAR), ≥ 60% (HISAT2) |
| Uniquely mapped | ≥ 60% |
| rRNA contamination | < 10% (ideally < 5%) |
| Gene body coverage | Uniform 5′ to 3′ (flag 3′ bias) |
| Assigned to features | ≥ 60% of mapped reads |
| Detected genes (≥ 10 counts) | ≥ 12,000 (human) |
| Strandedness | Matches library prep protocol |

## Metagenomics QC

| Metric | Target |
|--------|--------|
| Host removal rate | > 95% host reads removed |
| Classification rate (Kraken2) | 30–80% (sample-dependent) |
| Assembly N50 | > 1 kb |
| MAG completeness (CheckM2) | ≥ 50% (medium), ≥ 90% (high) |
| MAG contamination | < 10% (medium), < 5% (high) |
