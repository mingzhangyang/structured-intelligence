# Host Depletion Reference

Remove host reads from metagenomic samples before downstream analysis.

---

## Build a Bowtie2 Index

```bash
bowtie2-build ref.fa ref_idx
```

Run once per reference genome. Output: `ref_idx.1.bt2`, `.2.bt2`, `.3.bt2`, `.4.bt2`, `.rev.1.bt2`, `.rev.2.bt2`.

---

## Align Reads to Host

```bash
bowtie2 -x host_idx -1 R1.fq.gz -2 R2.fq.gz \
  --very-sensitive -p 8 -S host_aligned.sam 2> alignment_stats.txt
```

`alignment_stats.txt` contains overall alignment rate — review this before proceeding.

---

## Extract Unmapped Paired-End Reads

Three-step pipeline using samtools:

```bash
# Step 1 — convert and name-sort
samtools view -bS host_aligned.sam | samtools sort -n -o host_sorted.bam

# Step 2 — keep reads where BOTH mates are unmapped, exclude secondary alignments
samtools view -f 12 -F 256 host_sorted.bam > unmapped.bam

# Step 3 — convert to FASTQ
samtools fastq -1 clean_R1.fq.gz -2 clean_R2.fq.gz unmapped.bam
```

Flag reference:
| Flag | Meaning |
|------|---------|
| `-f 12` | Both read unmapped (flag 4) AND mate unmapped (flag 8) |
| `-F 256` | Exclude secondary alignments |

---

## Sensitivity Options

| Option | Use case |
|--------|---------|
| `--very-sensitive` | Clinical samples, low-biomass specimens — **recommended default** |
| `--sensitive` | General metagenomics with ample sequencing depth |
| `--fast` | Large pilot runs, quick QC checks only |

For clinical samples, always use `--very-sensitive` to minimise residual host contamination.

---

## BWA-MEM2 Alternative (Single-Step)

```bash
bwa-mem2 mem -t 8 ref.fa R1.fq.gz R2.fq.gz \
  | samtools sort -n \
  | samtools fastq -f 12 -F 256 \
      -1 clean_R1.fq.gz -2 clean_R2.fq.gz -
```

Streams directly from alignment to FASTQ; requires bwa-mem2 index built separately with `bwa-mem2 index ref.fa`.

---

## Host Contamination Benchmarks

| Sample type | Typical host fraction |
|-------------|----------------------|
| Human gut microbiome | 1–80% |
| Skin microbiome | 20–70% |
| Cell culture / tissue | >90% |
| Environmental (soil, water) | <5% |

---

## Common Gotchas

- **Use `-f 12` not `-f 4`** for paired-end data. `-f 4` only requires one mate to be unmapped, producing a mixed output where the partner read is host-derived.
- **Name-sorted BAM is required** before `samtools fastq`. Coordinate-sorted BAM will produce mismatched pairs.
- **Orphan reads** (one mate mapped, one unmapped) are excluded by `-f 12`. To retain the unmapped orphan, add a separate pass with `-f 4 -F 264` (unmapped, not secondary, not mate unmapped). Usually not worth the complexity.
- **Multiple host genomes** (e.g., human + mouse): align sequentially, extracting unmapped reads after each step, or concatenate reference genomes into a single index.
- **Check alignment rate** in `alignment_stats.txt`. Unexpectedly low rates may indicate wrong reference or corrupt index; unexpectedly high rates in environmental samples may indicate contamination during library prep.
