---
name: genome-read-alignment
description: Align short reads to a reference genome with BWA-MEM2, sort and index with samtools, and mark duplicates with picard.
---

# Skill: genome-read-alignment

## Use When

- User needs to align FASTQ reads to a reference genome.
- User wants to produce a coordinate-sorted, indexed BAM file.
- User needs to mark PCR or optical duplicates in aligned reads.
- User wants to add read group information (@RG) to alignments.

## Inputs

- Required:
  - Trimmed FASTQ file(s) (single-end or paired-end).
  - Reference FASTA, pre-indexed for BWA-MEM2.
- Optional:
  - Read group string (`@RG\tID:...\tSM:...\tPL:...\tLB:...\tPU:...`).
  - Number of threads (default: 4).
  - Output directory (default: current directory).
  - Temporary directory for sorting/dedup intermediates.
  - Optical duplicate pixel distance (default: 2500 for patterned flowcells).
  - Mark-duplicate tool choice: `picard` (default) or `samtools markdup`.

## Workflow

1. Validate that reference index files exist (`.0123`, `.amb`, `.ann`, `.bwt.2bit.64`, `.pac`, `.fai`, `.dict`).
2. Construct a read group string from sample metadata if one is not provided (fields: ID, SM, PL, LB, PU).
3. Run `bwa-mem2 mem` with the read group, piping output to `samtools sort` to produce a coordinate-sorted BAM.
4. Index the sorted BAM with `samtools index`.
5. Mark duplicates with `picard MarkDuplicates` (or `samtools markdup` if selected).
6. Index the deduplicated BAM.
7. Report alignment summary: total reads, mapped reads, properly paired reads, duplicate reads, mapping rate.

## Output Contract

- Coordinate-sorted deduplicated BAM file (`.bam`).
- BAM index file (`.bai`).
- Duplicate metrics file (picard MarkDuplicates output).
- Alignment summary statistics (total, mapped, properly paired, duplicates, mapping rate).

## Limits

- BWA-MEM2, samtools, and picard must be installed and available on `$PATH`.
- The BWA-MEM2 index must be pre-built (`bwa-mem2 index <ref.fa>`).
- Memory scales with reference genome size (~8 GB for human GRCh38).
- Picard requires a Java runtime (Java 8+).
- This skill handles single-sample alignment only; multi-sample merging is out of scope.
- Common failure cases:
  - Reference index files missing or incomplete (e.g., `.bwt.2bit.64` absent).
  - Read group string malformed or missing required fields (ID, SM).
  - Insufficient memory for BWA-MEM2 index loading (~8 GB for human genome).
