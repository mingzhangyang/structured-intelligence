# Taxonomic Profiling Reference — Kraken2, Bracken, MetaPhlAn 4

---

## Kraken2 Databases

| Database | Size | Notes |
|----------|------|-------|
| `standard` | ~70 GB | Bacteria, Archaea, Viruses, Human — general use |
| `k2_pluspf` (PlusPFP) | ~110 GB | Adds protozoa and fungi — broadest coverage |
| `k2_standard_08gb` | 8 GB | Memory-constrained servers; lower sensitivity |
| `minikraken2` | <1 GB | Development/testing only; poor sensitivity in production |

Databases must be fully loaded into RAM during a run. Verify available memory before selecting.

---

## Kraken2 Classification

```bash
kraken2 --db kraken2_db \
  --threads 8 \
  --report report.txt \
  --output output.txt \
  --paired R1.fq.gz R2.fq.gz
```

Optional: `--confidence 0.1` reduces false positives at the cost of sensitivity (default 0.0).

### Report Format

Columns (tab-separated):

```
percent  reads_covered  reads_directly  rank_code  taxon_id  name
```

Rank codes: `U` unclassified, `D` domain, `P` phylum, `C` class, `O` order, `F` family, `G` genus, `S` species.

---

## Bracken — Abundance Re-estimation

Bracken redistributes Kraken2 reads probabilistically to the desired taxonomic level.

### Build Bracken Database (once per read length)

```bash
bracken-build -d kraken2_db -t 8 -l 150
```

The `-l` value must match your actual read length.

### Run Bracken

```bash
bracken -d kraken2_db \
  -i report.txt \
  -o bracken_output.txt \
  -r 150 \
  -l S
```

`-l` level options: `S` species, `G` genus, `P` phylum. Re-run with different `-l` values on the same Kraken2 report without re-classifying.

---

## MetaPhlAn 4

Marker-gene–based profiler; does not require a large database in RAM.

```bash
metaphlan R1.fq.gz,R2.fq.gz \
  --input_type fastq \
  --nproc 8 \
  -o profile.txt \
  --bowtie2db metaphlan_db \
  --index mpa_vOct22_CHOCOPhlAnSGB_202212
```

Pass paired files as a comma-separated list (no space). Intermediate Bowtie2 alignments are cached in `--bowtie2out` (add flag to reuse across runs).

### Output Format

Relative abundance table with clade labels:

```
k__Bacteria|p__Firmicutes|...|s__Lactobacillus_acidophilus   0.342
```

Level prefixes: `k` kingdom, `p` phylum, `c` class, `o` order, `f` family, `g` genus, `s` species.

---

## Alpha Diversity

Compute from Bracken species table or MetaPhlAn output:

| Metric | Interpretation |
|--------|---------------|
| Shannon index | Balances richness and evenness; most commonly reported |
| Simpson index | Weighted toward dominant taxa |
| Species richness | Raw count; sensitive to sequencing depth |

Use `KronaTools`, `R vegan`, or `python skbio` to compute from abundance tables.

---

## Common Gotchas

- **Kraken2 RAM requirement**: the entire database must fit in memory. Use `--memory-mapping` to reduce RAM usage at the cost of speed.
- **`--confidence` threshold**: `0.1` is a reasonable default for reducing false positives; values above `0.3` substantially reduce sensitivity for rare taxa.
- **MetaPhlAn database/binary version mismatch** causes silent failures or incorrect profiles. Always pair the `--index` flag value with the version of `metaphlan` installed.
- **Bracken does not change presence/absence** — it only re-distributes read counts. A taxon absent from Kraken2 output will remain absent after Bracken.
- **Bracken database must be rebuilt** when the Kraken2 database is updated or when the read length changes.
