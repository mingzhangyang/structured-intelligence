# featureCounts and HTSeq-count Reference

## featureCounts (Subread Package)

```bash
featureCounts \
  -a genes.gtf \
  -o counts.txt \
  -T 8 \
  -s 0 \
  -p -B -C \
  sample1.bam sample2.bam sample3.bam
```

featureCounts can process multiple BAM files in one command, producing a single count matrix.

## featureCounts Key Flags

| Flag | Purpose |
|------|---------|
| `-a genes.gtf` | GTF annotation file |
| `-o counts.txt` | Output count matrix file |
| `-T 8` | Number of threads |
| `-s 0` | Strandedness: 0=unstranded, 1=stranded, 2=reverse-stranded |
| `-p` | Paired-end mode (count fragments, not reads) |
| `-B` | Both reads of a pair must map |
| `-C` | Do not count chimeric fragments (reads mapping to different chromosomes) |
| `-f` | Count at feature level (exon) rather than meta-feature (gene) |
| `--fracOverlap 0.2` | Minimum fraction of read that must overlap a feature |
| `-M` | Count multi-mapping reads (off by default; use with caution) |
| `-g gene_id` | GTF attribute to use as feature ID (default: gene_id) |

## featureCounts Output Format

Two files are produced:

- `counts.txt` — tab-delimited matrix:
  `Geneid | Chr | Start | End | Strand | Length | sample1.bam | sample2.bam | ...`
- `counts.txt.summary` — per-sample assignment statistics:
  `Assigned`, `Unassigned_NoFeatures`, `Unassigned_Ambiguity`, `Unassigned_MultiMapping`, etc.

Strip the first line (comment) and metadata columns 2–6 to get a clean count matrix for downstream tools.

## Determining Strandedness with RSeQC

```bash
infer_experiment.py -r genes.bed -i sample.bam
```

Output interpretation:

| RSeQC output | featureCounts `-s` | HTSeq-count `-s` | Salmon `-l` |
|---|---|---|---|
| ~50% "1++" / ~50% "1--" | `0` | `no` | `IU` |
| >75% "1++,1--" fraction | `1` | `yes` | `ISF` |
| >75% "2++,2--" fraction | `2` | `reverse` | `ISR` |

Most Illumina TruSeq Stranded kits produce reverse-stranded data (`-s 2`).

## HTSeq-count

```bash
htseq-count \
  -f bam \
  -r pos \
  -s reverse \
  -t exon \
  -i gene_id \
  sample.bam genes.gtf > counts.txt
```

BAM must be coordinate-sorted (`-r pos`). For name-sorted BAM use `-r name`.

## HTSeq-count Key Flags

| Flag | Values | Purpose |
|------|--------|---------|
| `-f` | `bam` / `sam` | Input format |
| `-r` | `pos` / `name` | BAM sort order |
| `-s` | `no` / `yes` / `reverse` | Strandedness |
| `-t` | `exon` | Feature type in GTF (column 3) |
| `-i` | `gene_id` | GTF attribute used as feature ID |
| `-m` | `union` / `intersection-strict` / `intersection-nonempty` | Overlap resolution mode |

## HTSeq-count Special Count Categories

| Category | Meaning |
|----------|---------|
| `__no_feature` | Read overlaps no annotated feature (intergenic) |
| `__ambiguous` | Read overlaps multiple features with incompatible assignments |
| `__too_low_aQual` | Read mapping quality below threshold (default: 10) |
| `__not_aligned` | Unmapped read |
| `__alignment_not_unique` | Multi-mapped read (NH > 1) |

A large `__no_feature` fraction (> 30%) usually indicates wrong strandedness.

## Common Gotchas

- Wrong strandedness is the most frequent error: if strandedness is reversed, most reads fall into `__no_feature` and true gene counts drop by 80–90%
- BAM must be coordinate-sorted for featureCounts; it will error on name-sorted BAMs unless `-p` mode is used with name-sorted input
- Use `-g gene_id` (default) to aggregate by gene; use `-g transcript_id` with `-f` to count per-exon or per-transcript
- The GTF `gene_id` attribute must match the identifiers expected downstream (Ensembl IDs vs. gene symbols); use `-g gene_name` to switch to symbols
- featureCounts is substantially faster than HTSeq-count for large datasets; prefer featureCounts unless HTSeq compatibility is required
