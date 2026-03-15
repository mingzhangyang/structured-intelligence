# FastQC & MultiQC Reference

## FastQC — Key Quality Modules

| Module | PASS/WARN/FAIL meaning |
|--------|------------------------|
| Per-base sequence quality | Median Phred ≥28 = PASS; <20 at any position = FAIL |
| Per-sequence quality scores | Distribution of mean read quality across all reads |
| Sequence duplication levels | % unique reads; WARN >20%, FAIL >50% |
| Adapter content | Fraction of reads with detectable adapter sequence |
| Per-sequence GC content | Deviation from expected bell curve |
| Per-base N content | N calls per cycle; any >5% = WARN |
| Overrepresented sequences | Single sequence >0.1% of total reads |

### Context-dependent interpretation

- **RNA-seq / amplicon**: Duplication WARN/FAIL is expected and normal — PCR amplification inflates counts. Do not flag as a QC failure.
- **WGS**: Duplication FAIL (>50%) is a genuine library concern.
- **Metagenomics**: GC content FAIL is expected — the sample contains many organisms with different GC compositions.
- **GC content FAIL (sharp peak shifted from expected)**: Often indicates rRNA contamination in RNA-seq. Confirm with rRNA depletion QC.
- **Adapter content WARN**: Trimming is required before alignment. FAIL means almost all reads need trimming.

## FastQC Key Flags

```bash
fastqc \
  --threads 8 \           # parallel jobs (one per file)
  --outdir ./fastqc_out \ # write results here (dir must exist)
  --extract \             # unzip the output .zip archive
  --nogroup \             # report every base position (not binned); use for short reads <75 bp
  sample_R1.fastq.gz sample_R2.fastq.gz
```

- `--nogroup` disables position grouping; useful when exact per-cycle quality matters for trimmer parameter tuning.
- `--threads` spawns one thread per input file, not per-base parallelism. Set to the number of files being processed simultaneously.

## MultiQC — Aggregating FastQC Reports

```bash
multiqc ./fastqc_out \       # scan directory for FastQC zip/html output
  --outdir ./multiqc_out \   # destination directory
  --force \                  # overwrite existing report
  --config multiqc_config.yaml \  # custom thresholds and display settings
  --ignore "*.bak"           # exclude files matching pattern
```

### Key aggregated plots to review

1. **General Statistics table** — read counts, %GC, %dups, %adapter per sample. Sort by column to spot outliers.
2. **FastQC: Per-base Sequence Quality heatmap** — rows = samples, columns = cycle. Horizontal red band = systematic quality drop.
3. **FastQC: Adapter Content overlay** — all samples overlaid on one axis. Any sample climbing toward 100% needs trimming.
4. **FastQC: Sequence Duplication Levels** — RNA-seq samples should cluster at similar duplication levels; an outlier may indicate PCR issues.
5. **FastQC: Per-sequence GC content** — a second peak or wide shoulders suggests contamination.

### Minimal multiqc_config.yaml

```yaml
title: "Project QC Report"
report_comment: "Pre-trimming FastQC summary"
extra_fn_clean_exts:
  - _R1_001
  - _R2_001
```

## Common Gotchas

- **Duplication WARN in RNA-seq is not a failure** — highly expressed transcripts will naturally produce many identical reads. Flag only if duplication is asymmetric between samples.
- **GC content FAIL can indicate rRNA contamination** — a sharp additional peak at ~55% GC in human RNA-seq is characteristic of rRNA reads escaping depletion.
- **Adapter content WARN means trimming is required** — upstream tools (aligners, assemblers) do not trim adapters and their presence reduces mapping rate.
- **FastQC --threads does not speed up a single large file** — parallelize by running multiple files at once.
- **MultiQC will not find results if the FastQC zip files are extracted into subdirectories** — keep zips or extracted folders at a predictable path depth and let MultiQC search recursively.
