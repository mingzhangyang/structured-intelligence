---
name: rnaseq-alignment-qc
description: RNA-seq-specific alignment quality assessment using RSeQC and Qualimap for gene body coverage, strandedness, and rRNA contamination.
---

# Skill: RNA-seq Alignment QC

## Use When

- User wants to assess RNA-seq alignment quality beyond basic mapping stats
- User needs to check strandedness of a library
- User wants to evaluate gene body coverage (5'-to-3' bias)
- User wants to measure rRNA contamination rate
- User needs to verify read distribution across genomic features (CDS, UTR, intron, intergenic)

## Inputs

- Required:
  - BAM file with index (`.bam` + `.bai`)
- Optional:
  - BED file of gene models (for RSeQC; available from UCSC or RSeQC downloads)
  - GTF annotation file (for Qualimap)
  - Output directory (default: `./alignment_qc_output`)
  - Species/genome build for rRNA intervals

## Workflow

1. Run RSeQC `infer_experiment.py` to determine library strandedness.
2. Run RSeQC `geneBody_coverage.py` for 5'-to-3' coverage profile across gene bodies.
3. Run RSeQC `read_distribution.py` for read distribution across genomic features (CDS, UTR, intron, intergenic).
4. Run RSeQC `inner_distance.py` for insert size distribution (paired-end data).
5. Run Qualimap `rnaseq` for comprehensive RNA-seq QC metrics.
6. Calculate rRNA rate from Qualimap output or custom rRNA interval overlap.
7. Compile summary: strandedness, gene body coverage shape, rRNA rate, feature distribution, junction saturation.
8. Flag metrics that fall outside recommended thresholds.

## Output Contract

- RSeQC strandedness report (text)
- Gene body coverage plot (PDF)
- Read distribution table (text)
- Inner distance plot (PDF, paired-end only)
- Qualimap HTML report
- Compiled QC summary (text)

## Limits

- RSeQC and Qualimap must be installed and available on PATH.
- BED gene model file is required for most RSeQC modules (downloadable from UCSC or RSeQC site).
- Qualimap requires Java to be installed.
- Qualimap memory scales with BAM size (approximately 2-4 GB for human genome BAMs).
- Common failure cases: missing BED file, BAM without index, Java not available for Qualimap.
