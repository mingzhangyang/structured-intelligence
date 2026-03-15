---
name: rnaseq-functional-enrichment
description: Gene set enrichment and over-representation analysis using clusterProfiler, gseapy, or fgsea, with GO, KEGG, and Reactome pathway databases.
---

# Skill: RNA-seq Functional Enrichment

## Use When

- User has a DE results table and wants to know which biological processes, pathways, or functions are enriched in up- or down-regulated genes
- User wants GO (biological process, molecular function, cellular component) enrichment
- User wants KEGG or Reactome pathway enrichment
- User wants gene set enrichment analysis (GSEA) using a ranked gene list
- User wants to compare enrichment across multiple contrasts or conditions

## Inputs

- Required:
  - DE results table (TSV with gene_id and padj or p-value columns) **OR** pre-ranked gene list (gene_id, ranking metric such as -log10(p)*sign(log2FC))
- Optional:
  - Organism database (default: `org.Hs.eg.db` for human)
  - Gene ID type: `SYMBOL`, `ENSEMBL`, or `ENTREZID` (default: `SYMBOL`)
  - FDR cutoff (default: `0.05`)
  - Analysis type: `ora` or `gsea` (default: `ora` for DE table input, `gsea` for ranked list)
  - Pathway databases: `go`, `kegg`, `reactome`, `msigdb` (default: `go,kegg`)
  - Minimum/maximum gene set size (default: min=5, max=500)
  - Output directory (default: `enrichment_results`)
  - Tool: `clusterProfiler` or `gseapy` (default: `clusterProfiler` for R environments; `gseapy` for Python-only environments)

## Workflow

1. Read DE results; extract gene IDs of significant genes (ORA) or rank all genes by -log10(padj)*sign(log2FoldChange) (GSEA). Strip Ensembl version suffixes (e.g., ENSG00000123.5 → ENSG00000123) if present.
2. Map gene IDs to ENTREZID using `bitr()` (clusterProfiler) or an annotation database. Deduplicate any genes that map to multiple Entrez IDs.
3. For ORA: run `enrichGO()` (BP, CC, MF), `enrichKEGG()`, and optionally `enrichPathway()` (Reactome) on the significant gene list.
4. For GSEA: run `gseGO()` (BP) and `gseKEGG()` on the full ranked gene vector.
5. Filter results by FDR threshold and gene set size limits.
6. Generate plots: dotplot (top 20 terms), barplot (top 20 pathways), network/emapplot (pathway overlap), gene-concept network (cnetplot).
7. Write all enrichment result tables as TSV and plots as PDFs to the output directory.
8. Report the top enriched terms per database.

## Output Contract

- GO enrichment table (TSV: ID, Description, GeneRatio, BgRatio, pvalue, p.adjust, geneID) — one file per ontology (BP, CC, MF)
- KEGG enrichment table (same format)
- Reactome enrichment table (same format, if requested)
- Dotplot PDF (top 20 GO BP, CC, MF terms)
- Barplot PDF (top 20 KEGG pathways)
- Network plot PDF (pathway overlap or gene-concept overlap)
- Session info text file

## Limits

- clusterProfiler requires R with `org.Hs.eg.db`, `ReactomePA`, `DOSE`, and `enrichplot` installed (see knowledge/sources/genomics/r-environment-setup.md)
- KEGG enrichment requires internet access (KEGG REST API) unless a local cache is used
- Reactome requires the `ReactomePA` package
- Gene ID conversion (`bitr`) may lose genes without an ENTREZID mapping (~10-20% for Ensembl IDs with version suffixes)
- GSEA requires a minimum of ~100 genes per gene set; rare pathways may be untestable
- Common failure cases: Ensembl IDs with version suffixes (ENSG00000123.5) must be stripped before ID conversion; KEGG organism code must match the species (hsa for human, mmu for mouse); gene sets with <5 or >500 genes are excluded by default size filters
