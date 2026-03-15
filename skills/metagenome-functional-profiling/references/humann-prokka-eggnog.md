# Functional Profiling Reference — HUMAnN 3, Prokka, eggNOG-mapper

---

## HUMAnN 3 — Community-Level Functional Profiling

### Database Setup

```bash
# Nucleotide database (~15 GB)
humann_databases --download chocophlan full chocophlan_db

# Protein database (~20 GB)
humann_databases --download uniref uniref90_diamond uniref_db
```

### Run HUMAnN 3

```bash
humann \
  --input sample.fastq.gz \
  --output humann_out \
  --threads 8 \
  --nucleotide-database chocophlan_db \
  --protein-database uniref_db \
  --taxonomic-profile metaphlan_profile.txt
```

Input must be a **single FASTQ file**. Concatenate paired-end reads before running:

```bash
cat R1.fq.gz R2.fq.gz > sample_concat.fastq.gz
```

Providing `--taxonomic-profile` (MetaPhlAn output) skips the internal MetaPhlAn step and improves speed.

### Output Files

| File | Contents | Units |
|------|---------|-------|
| `*_genefamilies.tsv` | UniRef90 gene family abundances | RPK |
| `*_pathabundance.tsv` | MetaCyc pathway abundances | RPK |
| `*_pathcoverage.tsv` | Fraction of pathway reactions detected | 0–1 |

Pathways are MetaCyc-based, not KEGG. For KEGG mapping, use `humann_regroup_table`.

### Normalisation

```bash
humann_renorm_table \
  --input genefamilies.tsv \
  --output genefamilies_cpm.tsv \
  --units cpm
```

CPM (copies per million) enables cross-sample comparisons. Apply to both `genefamilies.tsv` and `pathabundance.tsv`.

---

## Prokka — Gene Prediction and Annotation

```bash
prokka \
  --outdir prokka_out \
  --prefix sample \
  --kingdom Bacteria \
  --cpus 8 \
  contigs.fa
```

### Key Flags

| Flag | Description |
|------|-------------|
| `--kingdom` | `Bacteria`, `Archaea`, or `Viruses` |
| `--genus` / `--species` | Improves annotation specificity when taxonomy is known |
| `--proteins custom.faa` | Supplement with a custom protein database (checked first) |
| `--metagenome` | Use Prodigal metagenome mode for gene prediction |

Always use `--metagenome` for assembled metagenome contigs.

### Output Files

| Extension | Contents |
|-----------|---------|
| `.gff` | Gene annotation (use for downstream tools) |
| `.gbk` | GenBank format |
| `.faa` | Predicted protein sequences |
| `.ffn` | Nucleotide CDS sequences |
| `.txt` | Summary: gene counts by category |

---

## eggNOG-mapper — Ortholog and Functional Assignment

```bash
emapper.py \
  -i proteins.faa \
  --output eggnog_out \
  -m diamond \
  --cpu 8 \
  --data_dir eggnog_db
```

Input proteins can come from Prokka (`.faa`) or any predicted ORF set.

### Output: `.emapper.annotations`

Tab-separated; key columns:

| Column | Contents |
|--------|---------|
| `query` | Protein ID |
| `eggNOG_OGs` | Orthologous group assignments |
| `COG_cat` | COG functional category letter(s) |
| `Description` | Functional description |
| `KEGG_ko` | KEGG ortholog IDs |
| `KEGG_Pathway` | KEGG pathway IDs |
| `GO_terms` | Gene Ontology terms |

### COG Categories

| Code | Function |
|------|---------|
| J | Translation, ribosomal structure |
| K | Transcription |
| L | Replication, recombination, repair |
| D | Cell division and chromosome partitioning |
| T | Signal transduction |
| M | Cell wall, membrane, envelope |
| N | Cell motility |
| U | Intracellular trafficking, secretion |
| O | Post-translational modification, chaperones |
| C | Energy production and conversion |
| G | Carbohydrate transport and metabolism |
| E | Amino acid transport and metabolism |
| F | Nucleotide transport and metabolism |
| H | Coenzyme transport and metabolism |
| I | Lipid transport and metabolism |
| P | Inorganic ion transport and metabolism |
| Q | Secondary metabolite biosynthesis |
| R | General function prediction only |
| S | Function unknown |

---

## Common Gotchas

- **HUMAnN 3 paired-end input**: the tool accepts a single file only. Concatenate R1 and R2 before running — do not pass them separately.
- **Prokka `--kingdom` mismatch**: using `--kingdom Bacteria` on archaeal bins silences archaeal-specific gene predictors and produces sparse annotations. Run CheckM2 or GTDB-Tk first to confirm domain.
- **eggNOG database version**: the `.dmnd` database and `emapper.py` must be from the same release. Mixing versions produces silent mapping failures or format errors.
- **HUMAnN pathway basis**: output pathways are MetaCyc, not KEGG. For KEGG pathway analysis, regroup with `humann_regroup_table --custom kegg_pathways.tsv` after obtaining the mapping file from the HUMAnN utility database.
- **eggNOG database download**: use `download_eggnog_data.py -y` to fetch all required files into `eggnog_db/`. The core diamond database alone is insufficient for GO and pathway annotation.
