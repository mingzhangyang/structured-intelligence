---
name: genomics-reference-genomes
description: Standard reference genome builds, download sources, and indexing procedures for human and common model organisms.
---

# Reference Genomes

## Human

### GRCh38 / hg38

- **Primary assembly**: GRCh38.p14 (latest patch).
- **Analysis set (recommended)**: includes decoy sequences and EBV; masks HLA.
- NCBI: `GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz`
- Broad Institute: `gs://genomics-public-data/resources/broad/hg38/v0/Homo_sapiens_assembly38.fasta`
- GATK resource bundle: `gs://gcp-public-data--broad-references/hg38/v0/`
- 1000 Genomes: ftp.1000genomes.ebi.ac.uk

### T2T-CHM13 v2.0

- Telomere-to-telomere assembly; resolves centromeres, segmental duplications, rDNA.
- GitHub: github.com/marbl/CHM13
- Use case: improved variant calling in previously unresolvable regions.
- Note: annotation and tool support still catching up to GRCh38.

### GRCh37 / hg19 (legacy)

- Still used by some clinical pipelines and databases (e.g., ClinVar legacy).
- Liftover via UCSC liftOver or CrossMap for coordinate conversion.

## Indexing Requirements

| Tool | Index command | Output files |
|------|--------------|--------------|
| BWA-MEM2 | `bwa-mem2 index ref.fa` | `.0123`, `.amb`, `.ann`, `.bwt.2bit.64`, `.pac` |
| STAR | `STAR --runMode genomeGenerate --genomeFastaFiles ref.fa --sjdbGTFfile genes.gtf` | `Genome`, `SA`, `SAindex`, `chrName.txt`, etc. |
| HISAT2 | `hisat2-build ref.fa ref` | `.1.ht2` through `.8.ht2` |
| Bowtie2 | `bowtie2-build ref.fa ref` | `.1.bt2` through `.4.bt2`, `.rev.1.bt2`, `.rev.2.bt2` |
| Salmon | `salmon index -t transcriptome.fa -i salmon_idx` | hash-based index directory |
| kallisto | `kallisto index -i kallisto.idx transcriptome.fa` | single `.idx` file |
| samtools | `samtools faidx ref.fa` | `.fai` |
| GATK | `gatk CreateSequenceDictionary -R ref.fa` | `.dict` |
| Kraken2 | `kraken2-build --standard --db kraken2_db` | hash table + taxonomy |

## Common Model Organisms

| Organism | Build | Source |
|----------|-------|--------|
| Mouse | GRCm39 (mm39) | Ensembl, UCSC |
| Rat | mRatBN7.2 (rn7) | Ensembl |
| Zebrafish | GRCz11 (danRer11) | Ensembl |
| Drosophila | BDGP6 (dm6) | Ensembl, FlyBase |
| C. elegans | WBcel235 (ce11) | Ensembl, WormBase |
| Arabidopsis | TAIR10 | Ensembl Plants |
| E. coli K-12 | ASM584v2 | NCBI |
