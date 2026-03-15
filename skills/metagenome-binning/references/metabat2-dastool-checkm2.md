# Metagenome Binning Reference — MetaBAT2, DAS Tool, CheckM2

---

## Coverage Computation

MetaBAT2 requires per-contig coverage depth. Use the bundled helper tool after mapping reads back to the assembly:

```bash
# Map reads to assembly (if not already done)
bowtie2-build contigs.fa contigs_idx
bowtie2 -x contigs_idx -1 R1.fq.gz -2 R2.fq.gz -p 8 | \
  samtools sort -o sample.bam
samtools index sample.bam

# Compute depth
jgi_summarize_bam_contig_depths --outputDepth depth.txt sample.bam
```

For multi-sample binning, pass all BAM files to `jgi_summarize_bam_contig_depths` in a single call — co-assembly binning benefits significantly from coverage variation across samples.

---

## MetaBAT2

```bash
metabat2 -i contigs.fa -a depth.txt \
  -o bins/bin \
  -t 8 \
  --minContig 1500
```

### Output

One FASTA file per bin: `bins/bin.1.fa`, `bins/bin.2.fa`, etc. Contigs not assigned to any bin are written to `bins/bin.unbinned.fa`.

---

## DAS Tool — Multi-Binner Refinement

DAS Tool selects and merges bins from multiple independent binners to improve overall quality.

### Step 1 — Convert each binner's output to contig2bin TSV

```bash
Fasta_to_Contig2Bin.sh -i bins/ -e fa > metabat_contig2bin.tsv
# Repeat for MaxBin2, CONCOCT, etc.
```

TSV format: `contig_id<tab>bin_id` (one line per contig).

### Step 2 — Run DAS Tool

```bash
DAS_Tool \
  -i metabat_contig2bin.tsv,maxbin_contig2bin.tsv \
  -l MetaBAT2,MaxBin2 \
  -c contigs.fa \
  -o dastool_out \
  -t 8
```

`-l` labels must match the order of `-i` inputs. Output bins are in `dastool_out_DASTool_bins/`.

Default score threshold: `0.5` (lower → more bins retained, higher contamination risk). Adjust with `--score_threshold`.

---

## CheckM2 — Bin Quality Assessment

```bash
checkm2 predict \
  --input bins/ \
  --output-directory checkm2_out \
  --threads 8 \
  --database_path checkm2_db/uniref100.KO.1.dmnd
```

Download database once:

```bash
checkm2 database --download --path checkm2_db/
```

Database size: ~3 GB.

### Output Columns (`quality_report.tsv`)

| Column | Description |
|--------|-------------|
| Name | Bin filename |
| Completeness | Estimated completeness (%) |
| Contamination | Estimated contamination (%) |
| Completeness_Model_Used | ML model applied (Neural Network or Gradient Boost) |
| Translation_Table_Used | Genetic code detected |

---

## MIMAG Quality Classifications

| Tier | Completeness | Contamination |
|------|-------------|---------------|
| High-quality (HQ) | ≥ 90% | < 5% |
| Medium-quality (MQ) | ≥ 50% | < 10% |
| Low-quality (LQ) | < 50% | or ≥ 10% |

HQ bins suitable for publication require ≥ 90% completeness, < 5% contamination, and preferably a single rRNA operon.

---

## Common Gotchas

- **MetaBAT2 requires name-sorted BAM** when computing depth. `jgi_summarize_bam_contig_depths` expects coordinate-sorted and indexed BAM — ensure `samtools index` has been run.
- **DAS Tool score threshold**: the default `0.5` is conservative. For exploratory analysis, `0.3` recovers more bins; for submission-quality MAGs, keep `0.5` or higher.
- **CheckM2 database must be pre-downloaded**: the tool does not auto-fetch the database at runtime. Verify path before running.
- **Spurious bins**: bins with fewer than 50 contigs or less than 200 kb total length are often assembly artefacts or highly fragmented partial genomes. Flag these for manual review rather than automatic exclusion.
- **Multi-sample binning**: if co-assembling across samples, always generate per-sample BAMs and pass all to `jgi_summarize_bam_contig_depths`. Coverage covariation across samples is the strongest binning signal.
