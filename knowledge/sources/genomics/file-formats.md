---
name: genomics-file-formats
description: Reference for common genomics file formats used across NGS analysis pipelines.
---

# Genomics File Formats

## FASTQ

- Text-based format storing biological sequences and quality scores.
- Four lines per record: header (`@`), sequence, separator (`+`), quality (Phred+33 ASCII).
- Extensions: `.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`.
- Paired-end convention: `_R1`/`_R2` or `_1`/`_2` suffixes.
- Quality encoding: Illumina 1.8+ uses Phred+33 (ASCII 33–126, scores 0–93).

## SAM / BAM / CRAM

- **SAM** (Sequence Alignment/Map): tab-delimited text; header lines start with `@`.
- **BAM**: binary compressed SAM; requires index (`.bai`) for random access.
- **CRAM**: reference-based compression of alignment data; requires reference FASTA.
- Key fields: QNAME, FLAG, RNAME, POS, MAPQ, CIGAR, SEQ, QUAL.
- FLAG bit meanings: 0x1 paired, 0x2 proper pair, 0x4 unmapped, 0x10 reverse strand, 0x100 secondary, 0x400 duplicate, 0x800 supplementary.
- Sort orders: coordinate (default for variant calling), queryname (for some counting tools).

## VCF / BCF / gVCF

- **VCF** (Variant Call Format): tab-delimited; header lines start with `##`, column header with `#CHROM`.
- **BCF**: binary VCF; indexed with `.csi`.
- **gVCF**: genomic VCF; includes non-variant blocks for joint genotyping.
- Required columns: CHROM, POS, ID, REF, ALT, QUAL, FILTER, INFO.
- Per-sample fields in FORMAT/SAMPLE columns: GT, DP, AD, GQ, PL.
- INFO annotations: AC, AF, AN, DP, MQ, QD, FS, SOR.
- Multi-allelic sites: comma-separated ALT alleles.

## BED

- Tab-delimited: chrom, chromStart (0-based), chromEnd (exclusive).
- Optional columns: name, score, strand, thickStart, thickEnd, itemRgb, blockCount, blockSizes, blockStarts.
- BED3/BED6/BED12 refer to number of columns.
- Used for target regions (WES), gene models, and interval lists.

## GFF3 / GTF

- **GFF3**: tab-delimited, 9 columns; attributes as `key=value` pairs separated by `;`.
- **GTF** (GFF2): similar but attributes as `key "value";` pairs.
- Columns: seqname, source, feature, start (1-based), end (inclusive), score, strand, frame, attributes.
- Critical attributes: `gene_id`, `transcript_id`, `gene_name`, `gene_biotype`.
- Used by: STAR (genome indexing), featureCounts/HTSeq-count (read counting), SnpEff (annotation).
- Standard sources: Ensembl, GENCODE, RefSeq.

## FASTA / FASTA Index

- Header line starts with `>`, followed by sequence lines.
- `.fai` index: tab-delimited with NAME, LENGTH, OFFSET, LINEBASES, LINEWIDTH.
- `.dict` sequence dictionary: required by GATK; created with `samtools dict` or `picard CreateSequenceDictionary`.
- Common extensions: `.fa`, `.fasta`, `.fna`, `.fa.gz`.
