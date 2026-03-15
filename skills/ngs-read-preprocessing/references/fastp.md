# fastp Reference

## Overview

fastp is an all-in-one FASTQ quality control and adapter trimming tool. It performs adapter detection, quality filtering, length filtering, polyG/polyX trimming, UMI extraction, and generates HTML + JSON QC reports in a single pass.

## Core Command Pattern

```bash
# Single-end
fastp -i input.fastq.gz -o output.fastq.gz \
  -w 8 -q 20 -l 50 --json fastp.json --html fastp.html

# Paired-end
fastp \
  -i sample_R1.fastq.gz -I sample_R2.fastq.gz \
  -o sample_R1.trimmed.fastq.gz -O sample_R2.trimmed.fastq.gz \
  -w 8 -q 20 -l 50 \
  --detect_adapter_for_pe \
  --correction \
  --json fastp.json --html fastp.html
```

## Key Parameters

| Flag | Meaning |
|------|---------|
| `-i` / `-I` | Input R1 / R2 FASTQ (gzip supported) |
| `-o` / `-O` | Output R1 / R2 FASTQ |
| `-w` | Worker threads (default 3; max useful ~16) |
| `-q` | Minimum qualified Phred quality (default 15; use 20 for stricter filtering) |
| `-u` | Maximum % unqualified bases per read before read is discarded (default 40) |
| `-l` | Minimum read length after trimming (default 15; set to 50 for alignment) |
| `--adapter_sequence` | Explicit R1 adapter sequence (overrides auto-detection) |
| `--adapter_sequence_r2` | Explicit R2 adapter sequence |
| `--detect_adapter_for_pe` | Auto-detect adapters for paired-end data (recommended; do not also set `--adapter_sequence` unless overriding) |
| `--disable_adapter_trimming` | Skip adapter trimming entirely |
| `--poly_g_min_len` | Trim polyG tails ≥ N bases (default 10); **required for NovaSeq/NextSeq patterned flowcells** |
| `--correction` | Overlap-based base correction for PE reads; preserves strandedness |
| `--thread` | Alias for `-w` |

## Strandedness-Preserving Trimming

For stranded RNA-seq libraries, use `--correction` (overlap correction based on PE insert overlap). This fixes sequencing errors in the overlapping region without introducing strand bias and does not alter library orientation.

Do not use `--trim_poly_g` without `--poly_g_min_len` — the default polyG length threshold may be too aggressive for some library types.

## UMI Handling

```bash
fastp \
  -i R1.fastq.gz -I R2.fastq.gz \
  -o R1.trimmed.fastq.gz -O R2.trimmed.fastq.gz \
  --umi \
  --umi_loc read1 \   # read1, read2, per_read, or index1/index2
  --umi_len 12 \      # UMI length in bases
  --umi_prefix UMI    # prefix added to read name: @READNAME_UMI:ATCGATCG
```

UMI sequences are appended to the read name. Downstream deduplication tools (e.g., UMI-tools, fgbio) parse this field.

## JSON Output: Key Fields

```
summary.before_filtering.total_reads
summary.before_filtering.total_bases
summary.after_filtering.total_reads       # must equal before for paired-end (R1+R2 counted together)
summary.after_filtering.read1_mean_length
summary.after_filtering.q20_rate          # fraction of bases with Phred ≥ 20
summary.after_filtering.q30_rate          # fraction of bases with Phred ≥ 30
filtering_result.adapter_trimmed          # number of reads that had adapter removed
filtering_result.low_quality_reads        # reads dropped for quality
filtering_result.too_short_reads          # reads dropped for length
duplication.rate                          # estimated duplication rate
```

A q30_rate below 0.75 after filtering warrants investigation.

## Common Gotchas

- **Paired-end read counts must match after trimming.** fastp discards both mates when either mate fails filtering, so R1 and R2 output files always have identical read counts. If they differ, the run failed.
- **High duplication rate in fastp report is normal for RNA-seq.** fastp estimates duplication from the first ~10 million reads using exact sequence matching; highly expressed transcripts appear as duplicates. This is not a QC failure.
- **PolyG trimming is mandatory for NovaSeq and NextSeq patterned flowcells.** Dark cycles on these instruments produce G calls, generating artificial polyG tails. Set `--poly_g_min_len 10` (or lower) at minimum.
- **`--detect_adapter_for_pe` and `--adapter_sequence` can conflict.** If you specify both, the explicit sequence takes precedence for R1; auto-detection still applies to R2. Prefer `--detect_adapter_for_pe` alone unless you have a known non-standard adapter.
- **`-q` operates per base, not per read.** A read is discarded only if more than `-u`% of its bases fall below `-q`. Lowering `-u` (e.g., to 20) makes per-read filtering stricter.
