# RSeQC and Qualimap Alignment QC Reference

## RSeQC: infer_experiment.py

Determines library strandedness from a BAM file.

```bash
infer_experiment.py -r genes.bed -i sample.bam
```

Output example:
```
Fraction of reads failed to determine: 0.02
Fraction of reads explained by "1++,1--,2+-,2-+": 0.04
Fraction of reads explained by "1+-,1-+,2++,2--": 0.94
```

Interpretation:

| Pattern fractions | Strandedness | featureCounts | Salmon |
|---|---|---|---|
| ~0.5 / ~0.5 | Unstranded | `-s 0` | `IU` / `A` |
| >0.75 in "1++,1--" | Stranded-forward (ISF) | `-s 1` | `ISF` |
| >0.75 in "1+-,1-+" | Stranded-reverse (ISR) | `-s 2` | `ISR` |

Most TruSeq Stranded libraries show >90% in the "1+-,1-+" direction (ISR).

## RSeQC: geneBody_coverage.py

Plots read coverage across the 5' to 3' length of transcripts.

```bash
geneBody_coverage.py -r genes.bed -i sample.bam -o prefix
```

Plot interpretation:

| Pattern | Likely cause |
|---------|-------------|
| Flat / uniform | High-quality library |
| Drop toward 5' end (3'-biased) | Poly-A enrichment, RNA degradation |
| Drop toward 3' end (5'-biased) | Rare; seen in ribosome profiling or cap-selected protocols |
| Bimodal peaks | Contamination or mixed library types |

Use a high-coverage housekeeping gene list BED file for best results.

## RSeQC: read_distribution.py

Reports where reads map relative to annotated genomic features.

```bash
read_distribution.py -r genes.bed -i sample.bam
```

Output categories:

| Category | Expected fraction (mRNA-seq) |
|----------|------------------------------|
| `CDS_Exons` | >50% |
| `3'UTR_Exons` | 10–20% |
| `5'UTR_Exons` | 2–10% |
| `Introns` | 5–15% |
| `Intergenic` | <5% |

Total CDS + UTR exon fraction above 60% indicates a clean mRNA-seq library. High intronic fraction suggests genomic DNA contamination or unspliced pre-mRNA.

## RSeQC: junction_saturation.py

Assesses whether sequencing depth is sufficient to detect all splice junctions.

```bash
junction_saturation.py -r genes.bed -i sample.bam -o prefix
```

Output: plot of known/novel junction counts vs. subsampled read depth. A plateau indicates saturation; a still-rising curve means deeper sequencing would detect more junctions.

## BED File Preparation for RSeQC

RSeQC requires BED12 format (12-column BED with block/exon structure).

```bash
# Download prebuilt BED from UCSC Table Browser, or convert from GTF:
gtfToGenePred genes.gtf genes.genePred
genePredToBed genes.genePred genes.bed

# Or use pybedtools / UCSC utilities
```

Do not use BED6 — RSeQC will silently produce incorrect results without the block columns.

## Qualimap rnaseq

```bash
qualimap rnaseq \
  -bam sample.bam \
  -gtf genes.gtf \
  -outdir qc_dir \
  -p non-strand-specific
```

Strandedness options for `-p`:

| Value | Equivalent to |
|-------|--------------|
| `non-strand-specific` | Unstranded (`-s 0`) |
| `strand-specific-forward` | Forward-stranded (`-s 1`) |
| `strand-specific-reverse` | Reverse-stranded (`-s 2`) |

## Qualimap Output

The HTML report (`qualimapReport.html`) includes:

| Section | What to check |
|---------|--------------|
| Coverage bias | Should be low; high values indicate 3'/5' bias |
| Transcript coverage profile | Distribution of coverage across transcript positions |
| Reads genomic origin | Fraction in exons, introns, intergenic |
| rRNA rate | Ribosomal RNA contamination rate (requires rRNA annotation) |
| Duplication rate | High duplication (> 50%) suggests over-amplified library |

## Common Gotchas

- RSeQC requires BED12 format; BED6 files will cause silent errors in `geneBody_coverage.py` and `read_distribution.py`
- Qualimap takes a GTF file, not BED — do not swap these between tools
- `-p strand-specific-reverse` in Qualimap corresponds to `-s 2` in featureCounts; using the wrong value inverts junction and coverage statistics
- `infer_experiment.py` needs a reasonably deep BAM (> 1M mapped reads) to give reliable strandedness estimates; sparse BAMs will show ambiguous 50/50 fractions
- For large BAMs, `geneBody_coverage.py` can be slow; use `-l` to provide a list of high-confidence housekeeping genes to speed up the analysis
