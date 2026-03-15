# Variant Annotation Reference: SnpEff & VEP

## SnpEff — Annotation Command

```bash
snpEff ann \
  -v \                              # verbose
  -stats snpeff_stats.html \        # HTML summary report
  -csvStats snpeff_stats.csv \      # machine-readable stats
  -noLog \                          # disable usage logging
  GRCh38.105 \                      # database name (must match exactly)
  input.vcf.gz \
  > annotated.vcf
```

### Finding the correct database name

```bash
snpEff databases | grep -i "GRCh38"
snpEff databases | grep -i "hg38"
```

Common names: `GRCh38.105`, `GRCh38.99`, `hg38`. The version number matters — use the one matching your reference and annotation build.

### SnpEff Key Flags

| Flag | Meaning |
|------|---------|
| `-v` | Verbose; shows progress and warnings |
| `-stats` | HTML QC report with variant type breakdown |
| `-csvStats` | Same stats as CSV |
| `-noInteraction` | Disable intergenic interaction annotations |
| `-noLog` | Disable phone-home logging |
| `-cancer` | Enable cancer-specific annotations |
| `-Xmx8g` | JVM heap (pass before `ann`): `snpEff -Xmx8g ann ...` |

## SnpEff ANN Field Format

The `ANN` INFO field contains pipe-delimited annotation blocks, one per transcript:

```
ANN=A|missense_variant|MODERATE|BRCA1|ENSG00000012048|transcript|ENST00000357654.9|
    protein_coding|14/23|c.4327C>A|p.Arg1443Ser|4444/7088|4327/5592|1443/1863||
```

Field order:

| Position | Field | Example |
|----------|-------|---------|
| 1 | Allele | `A` |
| 2 | Effect | `missense_variant` |
| 3 | Putative impact | `MODERATE` |
| 4 | Gene name | `BRCA1` |
| 5 | Gene ID | `ENSG00000012048` |
| 6 | Feature type | `transcript` |
| 7 | Feature ID | `ENST00000357654.9` |
| 8 | Transcript biotype | `protein_coding` |
| 9 | Rank / total exons | `14/23` |
| 10 | HGVS.c | `c.4327C>A` |
| 11 | HGVS.p | `p.Arg1443Ser` |
| 12–14 | cDNA / CDS / protein position | `4444/7088` |
| 15 | Distance to feature | (for intergenic) |
| 16 | Errors/warnings | `WARNING_TRANSCRIPT_INCOMPLETE` |

## SnpEff Impact Categories

| Impact | Examples |
|--------|---------|
| HIGH | frameshift_variant, stop_gained, stop_lost, splice_donor_variant, splice_acceptor_variant, start_lost |
| MODERATE | missense_variant, inframe_insertion, inframe_deletion, protein_altering_variant |
| LOW | synonymous_variant, splice_region_variant, stop_retained_variant |
| MODIFIER | intron_variant, intergenic_region, upstream_gene_variant, downstream_gene_variant, 5_prime_UTR_variant, 3_prime_UTR_variant |

## VEP — Annotation Command

```bash
vep \
  --input_file input.vcf.gz \
  --output_file annotated.vcf.gz \
  --format vcf \
  --vcf \                           # output as VCF (not the default tab-delimited format)
  --compress_output bgzip \
  --cache \
  --dir_cache /path/to/vep_cache \
  --assembly GRCh38 \
  --merged \                        # use merged Ensembl + RefSeq cache
  --everything \                    # enable all annotation flags
  --fork 8
```

### VEP Key Flags (subset of `--everything`)

| Flag | Meaning |
|------|---------|
| `--pick` | Output one consequence per variant (highest impact transcript) |
| `--canonical` | Mark canonical transcript with CANONICAL=YES |
| `--protein` | Add protein sequence change |
| `--symbol` | Add gene symbol (HGNC) |
| `--biotype` | Add transcript biotype |
| `--af_gnomAD` | gnomAD allele frequencies |
| `--check_existing` | Annotate with known variants: ClinVar, dbSNP, COSMIC |
| `--sift b` | SIFT prediction and score |
| `--polyphen b` | PolyPhen-2 prediction and score |

### VEP Consequence Hierarchy (highest to lowest impact)

```
transcript_ablation
splice_acceptor_variant
splice_donor_variant
stop_gained
frameshift_variant
stop_lost
start_lost
transcript_amplification
inframe_insertion
inframe_deletion
missense_variant
protein_altering_variant
splice_region_variant
incomplete_terminal_codon_variant
stop_retained_variant
synonymous_variant
coding_sequence_variant
mature_miRNA_variant
5_prime_UTR_variant
3_prime_UTR_variant
intron_variant
intergenic_variant
```

When `--pick` is used, VEP selects the consequence highest in this hierarchy.

## Common Gotchas

- **SnpEff database name must match exactly.** `GRCh38` and `GRCh38.105` are different databases. Always confirm with `snpEff databases | grep`.
- **VEP cache must be downloaded separately and the version must match the VEP binary.** VEP version 110 requires cache version 110. Mismatches produce silently incomplete or incorrect annotations.
- **Both tools work best with bgzipped and tabix-indexed VCF input.** Uncompressed VCFs work but are slower; ensure `.vcf.gz` has a corresponding `.vcf.gz.tbi` file.
- **Multiple ANN entries per variant in SnpEff output.** One `ANN` field can contain many pipe-delimited blocks separated by commas, one per affected transcript. Parsers must split on `,` before splitting on `|`.
- **VEP `--everything` enables `--check_existing`, which requires an internet connection or a full local cache.** In offline HPC environments, omit flags that require external lookups or ensure the cache is complete.
- **SnpEff needs more JVM heap for large VCFs.** Pass heap size before the subcommand: `snpEff -Xmx16g ann GRCh38.105 input.vcf.gz`.
