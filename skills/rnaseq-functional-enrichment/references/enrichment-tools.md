# Functional Enrichment Tools Reference

## clusterProfiler Key Functions

| Function | Purpose |
|----------|---------|
| `bitr(gene, fromType, toType, OrgDb)` | Translate gene IDs between types (SYMBOL ↔ ENSEMBL ↔ ENTREZID) |
| `enrichGO(gene, universe, OrgDb, ont, ...)` | ORA against Gene Ontology (ont = "BP", "CC", or "MF") |
| `enrichKEGG(gene, universe, organism, ...)` | ORA against KEGG pathway database |
| `enrichPathway(gene, universe, organism, ...)` | ORA against Reactome (requires ReactomePA) |
| `gseGO(geneList, OrgDb, ont, ...)` | GSEA against Gene Ontology |
| `gseKEGG(geneList, organism, ...)` | GSEA against KEGG |
| `gsePathway(geneList, organism, ...)` | GSEA against Reactome (requires ReactomePA) |
| `pairwise_termsim(result)` | Compute term-term similarity; required before `emapplot()` |
| `dotplot(result, showCategory = 20)` | Dotplot of top enriched terms |
| `barplot(result, showCategory = 20)` | Barplot of top enriched terms |
| `emapplot(result)` | Enrichment map (network of overlapping gene sets) |
| `cnetplot(result, foldChange = ...)` | Gene-concept network (genes linked to terms) |
| `ridgeplot(result)` | Density plot of ranked gene scores per gene set (GSEA only) |
| `gseaplot2(result, geneSetID = ...)` | Enrichment score plot for a single gene set (GSEA only) |

## ORA vs GSEA

| Aspect | ORA (Over-Representation Analysis) | GSEA (Gene Set Enrichment Analysis) |
|--------|-------------------------------------|--------------------------------------|
| Input | Binary gene list (significant vs background) | All genes ranked by a continuous score |
| Statistical test | Hypergeometric / Fisher's exact test | Permutation-based enrichment score |
| Threshold dependency | Requires an arbitrary significance cutoff | Threshold-free; uses the full ranking |
| Sensitivity | May miss subtle but coordinated changes | Detects weak but consistent signals |
| Preferred use | Clear-cut DE with well-powered experiments | Large datasets; when cutoff choice is ambiguous |
| Minimum gene count | ~10 significant genes | ~100 genes per gene set for reliable permutation |

## GO Ontologies

| Code | Ontology | Describes |
|------|----------|-----------|
| BP | Biological Process | Multi-step molecular events (e.g., apoptosis, cell cycle) |
| CC | Cellular Component | Location of gene product (e.g., nucleus, mitochondria) |
| MF | Molecular Function | Biochemical activity (e.g., kinase activity, DNA binding) |

GO terms are organized in a directed acyclic graph (DAG); parent terms are more general than child terms. clusterProfiler uses `simplify()` to remove redundant GO terms after enrichment.

## KEGG Organism Codes

| Code | Species |
|------|---------|
| `hsa` | Homo sapiens (human) |
| `mmu` | Mus musculus (mouse) |
| `rno` | Rattus norvegicus (rat) |
| `dre` | Danio rerio (zebrafish) |
| `dme` | Drosophila melanogaster |
| `cel` | Caenorhabditis elegans |
| `sce` | Saccharomyces cerevisiae |

KEGG enrichment (`enrichKEGG`, `gseKEGG`) requires internet access to the KEGG REST API at runtime. Use `use_internal_data = TRUE` in clusterProfiler for offline analysis with a cached copy.

## Reactome

- Requires the `ReactomePA` Bioconductor package (imports from ReactomePA, which depends on `graphite`).
- Accepts **Entrez IDs only** — gene ID conversion must happen before calling `enrichPathway()` or `gsePathway()`.
- Organism argument uses full names: `"human"`, `"mouse"`, `"rat"`, `"zebrafish"`, `"celegans"`, `"yeast"`, `"fly"`, `"bovine"`.

## MSigDB Gene Sets

MSigDB (Molecular Signatures Database) gene sets can be loaded with the `msigdbr` package and passed to `clusterProfiler::GSEA()` or `enricher()`.

| Category | Code | Description |
|----------|------|-------------|
| H | Hallmark | 50 well-defined biological states/processes |
| C1 | Positional | Gene sets by chromosomal position |
| C2 | Curated | Canonical pathways (KEGG, Reactome, BioCarta, WikiPathways) |
| C3 | Regulatory | Motif and microRNA targets |
| C4 | Computational | Cancer gene neighborhoods |
| C5 | Ontology | GO gene sets (BP, CC, MF) |
| C6 | Oncogenic | Oncogenic signature gene sets |
| C7 | Immunological | Immune cell type signatures |
| C8 | Cell type | Single-cell marker gene sets |

```r
library(msigdbr)
# Retrieve human Hallmark gene sets
h_sets <- msigdbr(species = "Homo sapiens", category = "H")
h_t2g  <- h_sets[, c("gs_name", "entrez_gene")]  # for GSEA() / enricher()
```

## Ranking Metric for GSEA

The standard ranking metric for RNA-seq GSEA is:

```
score = -log10(padj) * sign(log2FoldChange)
```

- Highly up-regulated significant genes get large positive scores.
- Highly down-regulated significant genes get large negative scores.
- Genes with padj = NA should be removed or assigned score = 0.
- Use `padj` in preference to `pvalue` to account for multiple testing; replace any `padj = 0` values with `1e-300` before taking the log to avoid `Inf`.

## Common Gotchas

1. **Ensembl version suffixes**: IDs like `ENSG00000123456.5` fail `bitr()` silently or with warnings. Always strip the version suffix with `sub("\\.[0-9]+$", "", ids)` before conversion.

2. **Duplicated gene IDs after bitr()**: One Ensembl ID can map to multiple Entrez IDs. Deduplicate by keeping one Entrez ID per original ID (e.g., first hit or highest-score hit for GSEA).

3. **KEGG organism codes are separate from OrgDb names**: `hsa` (KEGG) corresponds to `org.Hs.eg.db` (OrgDb). Mixing these up causes "organism not found" errors.

4. **KEGG internal gene ID format**: KEGG uses `hsa:1234` internally; `enrichKEGG` handles this automatically. Do not prefix Entrez IDs manually.

5. **Gene set size filters**: Default `minGSSize = 5`, `maxGSSize = 500`. Very small gene sets are statistically unreliable; very large ones are biologically uninformative. Adjust based on the analysis context.

6. **GSEA permutation count**: The default `nPerm = 1000` is a minimum. For publication-quality results, use `nPerm = 10000`. Runtime increases linearly.

7. **pairwise_termsim() required before emapplot()**: Forgetting this step causes an error. Always call `result <- pairwise_termsim(result)` first.

8. **ReactomePA organism strings differ from KEGG codes**: Use `"human"` not `"hsa"` with ReactomePA functions.

9. **gseapy Enrichr libraries change over time**: Library names like `GO_Biological_Process_2023` include a year; check available libraries with `gseapy.get_library_name()` if a library name returns 404.

10. **Background gene universe for ORA**: Always supply the full tested gene universe (`universe` argument) rather than defaulting to all annotated genes, to avoid inflated significance.
