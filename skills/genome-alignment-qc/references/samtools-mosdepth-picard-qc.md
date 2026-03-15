# Alignment QC Reference: samtools / mosdepth / Picard

## samtools flagstat

```bash
samtools flagstat -@ 4 sample.markdup.bam > sample.flagstat.txt
```

### Key output fields

| Field | Interpretation |
|-------|---------------|
| `total` | All records including supplementary and secondary |
| `mapped` | Records with FLAG bit 0x4 unset |
| `properly paired` | Both mates mapped in expected orientation/distance |
| `singletons` | One mate mapped, the other did not |
| `duplicates` | Records flagged as duplicate (0x400) |

**Mapping rate** = `mapped / total`. Typical thresholds: >95% for WGS human, >90% for RNA-seq, >80% for metagenomics host-depleted samples.

Low mapping rate causes: wrong reference genome, poor trimming, high contamination, or library preparation failure.

## samtools stats

```bash
samtools stats -@ 4 sample.markdup.bam > sample.stats.txt
# Extract summary numbers:
grep "^SN" sample.stats.txt | cut -f2,3
```

### Key SN (Summary Numbers) fields

| Key | Meaning |
|-----|---------|
| `average length` | Mean read length after clipping |
| `average quality` | Mean base quality across all reads |
| `insert size average` | Mean PE insert size |
| `insert size standard deviation` | Spread of insert size distribution |
| `reads duplicated` | Count of duplicate-flagged reads |
| `bases mapped (cigar)` | Bases contributing to alignment (not soft-clipped) |

The `IS:` section contains the full insert size histogram as tab-separated values (insert_size, count, count_inward, count_outward, count_other).

## mosdepth — Coverage Analysis

```bash
mosdepth \
  --threads 4 \
  --by 500 \                    # window size in bp (use --by targets.bed for WES)
  --quantize 0:1:10:30:100: \   # bin coverage into depth categories
  sample_prefix \
  sample.markdup.bam
```

### Output files

| File | Content |
|------|---------|
| `<prefix>.mosdepth.global.dist.txt` | CDF: fraction of genome at ≥ N× coverage |
| `<prefix>.mosdepth.summary.txt` | Per-chromosome mean depth |
| `<prefix>.regions.bed.gz` | Per-window depth values |
| `<prefix>.quantized.bed.gz` | Depth bins (when `--quantize` used) |

### Reading the CDF (global.dist.txt)

Columns: `chromosome`, `depth`, `fraction_at_or_above`. The row `total  30  0.95` means 95% of the genome has ≥30× coverage. For WGS QC, check that the `total` row at your target depth exceeds your coverage threshold (e.g., ≥0.90 at 30×).

### Target-restricted analysis (WES)

```bash
mosdepth --threads 4 --by targets.bed sample_prefix sample.markdup.bam
```

Use `--by <bed>` instead of `--by <window_size>` to restrict analysis to capture regions. The BED chromosome names must match the BAM header.

## Picard CollectInsertSizeMetrics

```bash
picard CollectInsertSizeMetrics \
  -I sample.markdup.bam \
  -O sample.insert_size_metrics.txt \
  -H sample.insert_size_histogram.pdf
```

### Key output columns

| Column | Meaning |
|--------|---------|
| `MEDIAN_INSERT_SIZE` | Robust center of distribution |
| `MEAN_INSERT_SIZE` | Arithmetic mean (sensitive to outliers) |
| `STANDARD_DEVIATION` | Spread |
| `READ_PAIRS` | Number of pairs used for estimation |

Expected insert sizes: WGS ~350–450 bp, WES ~200–300 bp, ATAC-seq bimodal (200 bp and 400 bp peaks). A very narrow distribution or bimodal unexpected peak indicates degraded DNA or library issues.

## Picard CollectAlignmentSummaryMetrics

```bash
picard CollectAlignmentSummaryMetrics \
  -R ref.fa \
  -I sample.markdup.bam \
  -O sample.alignment_summary_metrics.txt
```

### Key output columns

| Column | Meaning |
|--------|---------|
| `PCT_PF_READS_ALIGNED` | Fraction of pass-filter reads that aligned |
| `PCT_READS_ALIGNED_IN_PAIRS` | Fraction aligned as proper pairs |
| `STRAND_BALANCE` | 0.5 = balanced; deviation may indicate strand bias |
| `PCT_CHIMERAS` | Fraction of reads with chimeric alignments (>1% warrants investigation) |

## Common Gotchas

- **mosdepth requires an indexed BAM.** The `.bai` index must be in the same directory. Run `samtools index` before mosdepth.
- **Insert size metrics are only meaningful for paired-end data.** Running CollectInsertSizeMetrics on single-end data will produce an empty or misleading output.
- **Chromosome naming must match between BAM and BED.** A BED using `chr1` against a BAM with `1` (or vice versa) will produce zero results without an error. Use `samtools view -H` to confirm BAM contig names.
- **mosdepth `--quantize` thresholds must be colon-separated with a trailing colon.** Example: `0:1:10:30:100:` — the trailing colon closes the last bin.
- **flagstat `total` includes secondary and supplementary alignments.** For a true primary alignment mapping rate, filter with `samtools view -F 2304` before running flagstat, or use the `primary mapped` line in newer samtools versions.
