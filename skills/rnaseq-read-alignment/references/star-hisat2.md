# STAR and HISAT2 Alignment Reference

## STAR Genome Index Generation

```bash
STAR \
  --runMode genomeGenerate \
  --genomeFastaFiles ref.fa \
  --sjdbGTFfile genes.gtf \
  --genomeDir star_idx \
  --runThreadN 8 \
  --genomeSAindexNbases 14
```

Use `--genomeSAindexNbases 14` for small genomes (< 1 Gb). For human/mouse, default (14–14) is fine. Formula: `min(14, log2(GenomeLength)/2 - 1)`.

## STAR Alignment Key Flags

| Flag | Purpose |
|------|---------|
| `--runThreadN` | Number of threads |
| `--genomeDir` | Path to genome index directory |
| `--readFilesIn R1.fq.gz R2.fq.gz` | Input reads (paired-end) |
| `--readFilesCommand zcat` | Required for .gz input |
| `--outSAMtype BAM SortedByCoordinate` | Output sorted BAM directly |
| `--outFileNamePrefix sample_` | Prefix for all output files |
| `--outSAMstrandField intronMotif` | Adds XS tag for unstranded libraries (needed by Cufflinks) |
| `--quantMode GeneCounts` | Output per-gene read counts |
| `--twopassMode Basic` | Enable automatic two-pass alignment |

## STAR Two-Pass Mode

Two-pass alignment improves accuracy for novel junctions:

- **First pass**: discovers splice junctions from the data
- **Second pass**: re-aligns reads using the discovered junction database
- Use `--twopassMode Basic` for automatic two-pass (STAR handles both passes internally)
- Especially beneficial for samples with many novel splice sites or fusion detection

```bash
STAR \
  --runThreadN 8 \
  --genomeDir star_idx \
  --readFilesIn R1.fq.gz R2.fq.gz \
  --readFilesCommand zcat \
  --outSAMtype BAM SortedByCoordinate \
  --outFileNamePrefix sample_ \
  --twopassMode Basic \
  --quantMode GeneCounts
```

## STAR Output Files

| File | Contents |
|------|---------|
| `*Log.final.out` | Alignment summary: uniquely mapped %, multi-mapped %, unmapped % |
| `*SJ.out.tab` | Detected splice junctions with counts and intron motifs |
| `*ReadsPerGene.out.tab` | Gene counts (requires `--quantMode GeneCounts`); columns: gene, unstranded, stranded-fwd, stranded-rev |
| `*Aligned.sortedByCoord.out.bam` | Final alignment BAM |

## HISAT2 Index Generation

```bash
# Build main index
hisat2-build ref.fa ref_idx

# Extract splice sites for splice-aware alignment (optional but recommended)
hisat2_extract_splice_sites.py genes.gtf > splice_sites.txt
hisat2_extract_exons.py genes.gtf > exons.txt

# Build index with splice site and exon info
hisat2-build --ss splice_sites.txt --exon exons.txt ref.fa ref_idx
```

## HISAT2 Alignment Key Flags

| Flag | Purpose |
|------|---------|
| `-x ref_idx` | Index prefix |
| `-1 R1.fq.gz -2 R2.fq.gz` | Paired-end input |
| `--threads 8` | Number of threads |
| `-S sample.sam` | SAM output (pipe to samtools for BAM) |
| `--dta` | Downstream transcript assembly (required for StringTie) |
| `--rna-strandness RF` | Reverse-stranded PE (FR = forward-stranded PE) |

```bash
hisat2 -x ref_idx -1 R1.fq.gz -2 R2.fq.gz \
  --threads 8 --dta --rna-strandness RF \
  | samtools sort -o sample.bam -
samtools index sample.bam
```

HISAT2 does not output a sorted BAM directly — sort with `samtools sort` after alignment.

## Memory Requirements

| Tool | Human genome | Mouse genome |
|------|-------------|-------------|
| STAR | ~32 GB RAM | ~8 GB RAM |
| HISAT2 | ~8 GB RAM | ~4 GB RAM |

## Common Gotchas

- STAR index must be built with the same STAR binary version used for alignment; mismatches cause cryptic errors
- `.gz` input requires `--readFilesCommand zcat` — omitting this causes STAR to read binary gzip data
- Reduce `--genomeSAindexNbases` for genomes < 1 Gb or STAR will fail with a segfault
- HISAT2 requires a separate `samtools sort` step; STAR can sort internally with `--outSAMtype BAM SortedByCoordinate`
- `--outSAMstrandField intronMotif` is needed for unstranded libraries going into Cufflinks/StringTie
