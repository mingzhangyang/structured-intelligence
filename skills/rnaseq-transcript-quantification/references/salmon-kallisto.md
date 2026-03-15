# Salmon and kallisto Quantification Reference

## Salmon Index

```bash
# Standard index
salmon index -t transcriptome.fa -i salmon_idx

# For GENCODE transcriptomes
salmon index -t transcriptome.fa -i salmon_idx --gencode

# Selective alignment with genome as decoy (recommended for accuracy)
cat transcriptome.fa genome.fa > gentrome.fa
grep "^>" genome.fa | cut -d " " -f 1 | sed 's/>//' > decoys.txt
salmon index -t gentrome.fa -i salmon_idx --decoys decoys.txt -k 31
```

The `--decoys` approach reduces false mappings by accounting for reads that originate from genomic regions not in the transcriptome.

## Salmon Quantification Key Flags

| Flag | Purpose |
|------|---------|
| `-i salmon_idx` | Path to Salmon index |
| `-l A` | Auto-detect library type (recommended) |
| `-1 R1.fq.gz -2 R2.fq.gz` | Paired-end input |
| `--validateMappings` | More sensitive mapping; recommended for all runs |
| `--seqBias` | Correct for sequence-specific bias |
| `--gcBias` | Correct for GC content bias |
| `--numBootstraps 100` | Bootstrap replicates (required for sleuth) |
| `-p 8` | Number of threads |
| `-o sample_out` | Output directory |

```bash
salmon quant \
  -i salmon_idx -l A \
  -1 R1.fq.gz -2 R2.fq.gz \
  --validateMappings --gcBias --seqBias \
  -p 8 -o sample_out
```

## Salmon Library Type Codes

| Code | Meaning |
|------|---------|
| `A` | Auto-detect (use this unless you have a reason not to) |
| `IU` | Inward, unstranded, paired-end |
| `ISF` | Inward, stranded, forward (first read matches transcript strand) |
| `ISR` | Inward, stranded, reverse (first read is reverse complement of transcript strand) |

Most Illumina TruSeq Stranded libraries are `ISR`.

## Salmon Output: quant.sf Columns

| Column | Description |
|--------|-------------|
| `Name` | Transcript ID |
| `Length` | Transcript length (bp) |
| `EffectiveLength` | Length adjusted for fragment length distribution and bias |
| `TPM` | Transcripts per million |
| `NumReads` | Estimated read count (can be fractional) |

## kallisto Index

```bash
kallisto index -i kallisto.idx transcriptome.fa
```

## kallisto Quantification

```bash
# Paired-end
kallisto quant -i kallisto.idx -o out_dir -b 100 R1.fq.gz R2.fq.gz

# Single-end (must provide estimated fragment length and SD)
kallisto quant -i kallisto.idx -o out_dir -b 100 \
  --single -l 200 -s 20 reads.fq.gz
```

`-b 100` runs 100 bootstrap replicates, required for uncertainty estimation with sleuth.

## kallisto Output: abundance.tsv Columns

| Column | Description |
|--------|-------------|
| `target_id` | Transcript ID |
| `length` | Transcript length (bp) |
| `eff_length` | Effective length |
| `est_counts` | Estimated read counts |
| `tpm` | Transcripts per million |

## tximport Integration (R)

```r
library(tximport)

# Build tx2gene mapping (transcript ID -> gene ID)
# tx2gene must be a data.frame with columns: tx_id, gene_id

# Import Salmon output
files <- file.path("results", samples, "quant.sf")
names(files) <- samples
txi <- tximport(files, type = "salmon", tx2gene = tx2gene)

# For DESeq2 (handles length-bias internally)
library(DESeq2)
dds <- DESeqDataSetFromTximport(txi, colData = coldata, design = ~ condition)

# For edgeR (use lengthScaledTPM to account for length bias)
txi_edge <- tximport(files, type = "salmon", tx2gene = tx2gene,
                     countsFromAbundance = "lengthScaledTPM")
```

`txi` contains: `counts`, `abundance` (TPM), `length` (effective lengths).

## Common Gotchas

- The transcriptome FASTA must match the genome annotation version — mixing Ensembl 105 transcriptome with Ensembl 110 GTF produces incorrect tx2gene mappings
- Salmon mapping rate below 50% suggests a wrong or mismatched reference; check with `--validateMappings` output log
- kallisto single-end mode requires estimated fragment length (`-l`) and standard deviation (`-s`); these are typically obtained from the insert size distribution of a paired-end run on the same library type
- Every transcript ID in `quant.sf` must appear in `tx2gene`; unrecognized IDs cause tximport to error or silently drop data — use `ignoreTxVersion = TRUE` if version suffixes differ
- Do not use `--gencode` flag with non-GENCODE transcriptomes; it strips pipe-delimited fields from IDs incorrectly
