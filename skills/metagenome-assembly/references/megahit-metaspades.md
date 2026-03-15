# Metagenome Assembly Reference — MEGAHIT and metaSPAdes

---

## MEGAHIT

Recommended for large, complex communities or memory-constrained environments.

```bash
megahit -1 R1.fq.gz -2 R2.fq.gz \
  -o megahit_out \
  -t 8 \
  -m 0.9 \
  --min-contig-len 1000
```

### Key Flags

| Flag | Description |
|------|-------------|
| `-t` | Threads |
| `-m` | Max memory fraction of available RAM (e.g., `0.9`); use `--memory` for absolute GB |
| `--min-contig-len` | Discard contigs shorter than this length (bp) |
| `--k-min` / `--k-max` / `--k-step` | k-mer sweep range and step; defaults: 21–141–10 |
| `--presets meta-large` | Optimised k-mer sweep for complex, high-diversity communities |

### Output

`megahit_out/final.contigs.fa` — all contigs at or above `--min-contig-len`.

---

## metaSPAdes

Higher contiguity than MEGAHIT on simpler communities; requires substantially more RAM.

```bash
spades.py --meta \
  -1 R1.fq.gz -2 R2.fq.gz \
  -o metaspades_out \
  -t 8 \
  -m 200 \
  -k 21,33,55,77
```

### Key Flags

| Flag | Description |
|------|-------------|
| `--meta` | Enable metagenome assembly mode |
| `-k` | Comma-separated k-mer sizes (odd integers only) |
| `-t` | Threads |
| `-m` | Memory limit in GB |
| `--only-assembler` | Skip error-correction step (use when reads are already corrected) |

### Output

| File | Contents |
|------|---------|
| `contigs.fasta` | All assembled contigs |
| `scaffolds.fasta` | Scaffolded sequences (use for binning) |
| `assembly_graph.fastg` | Assembly graph for Bandage visualisation |

---

## Assembly QC

### Quick statistics (assembly-stats or seqtk)

```bash
# assembly-stats
assembly-stats contigs.fa

# seqtk size
seqtk size contigs.fa
```

Metrics to record: N50, N90, L50, total length, max contig length, contig count.

### MetaQUAST (comprehensive)

```bash
metaquast.py contigs.fa -o quast_out --threads 8
```

Runs reference-free by default; add `-r reference.fa` when a reference genome is available for comparison. Produces HTML report with misassembly and coverage statistics.

---

## Filtering Contigs for Binning

Binners require a minimum contig length to generate reliable coverage and tetranucleotide signatures:

```bash
seqtk seq -L 1500 contigs.fa > filtered.fa
```

Recommended thresholds:
| Purpose | Minimum length |
|---------|---------------|
| Binning | 1500–2500 bp |
| Functional annotation | 500 bp |
| Taxonomic classification | 1000 bp |

---

## Common Gotchas

- **metaSPAdes RAM**: plan for 2–4× the total estimated genome size in memory. A 100-sample gut metagenome may require 200+ GB. MEGAHIT is a safer default on shared clusters.
- **MEGAHIT on very complex communities**: the assembler may terminate early with fragmented output. Try `--presets meta-large` or manually widen the k-mer sweep (`--k-min 21 --k-max 141 --k-step 12`).
- **Do not aggressively quality-filter before assembly**: trimming adapters and removing low-quality bases is correct, but hard-trimming to Q30 shortens reads and reduces assembly contiguity. Assemblers handle base-quality variation internally.
- **Re-running metaSPAdes**: use `--continue` to resume a failed run; do not restart from scratch unless the output directory is removed first.
- **MEGAHIT output directory must not exist**: delete or rename the output directory before re-running.
