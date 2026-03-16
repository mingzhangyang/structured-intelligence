---
name: stat-nonlinear-embedding
description: Embed high-dimensional data into 2D using t-SNE or UMAP for exploratory visualization of sample or cell relationships.
---

# Skill: Nonlinear Dimensionality Reduction

## Use When

- User wants to visualize cell populations or sample clusters in 2D after scRNA-seq, flow cytometry, or omics analysis
- User wants a t-SNE or UMAP plot colored by cell type, cluster, or metadata
- User needs a nonlinear embedding that preserves local neighborhood structure
- Use `stat-pca` for linear embedding first, then this skill for refined visualization

## Inputs

- Required:
  - Data matrix (CSV or TSV): rows = samples/cells, columns = features; OR a precomputed PCA coordinate table
- Optional:
  - Embedding method: `umap` (default) or `tsne`
  - Input type: `raw` (default) or `pca` (precomputed PC coordinates)
  - For t-SNE: perplexity (default: `30`), max iterations (default: `1000`), learning rate (default: `200`)
  - For UMAP: n_neighbors (default: `15`), min_dist (default: `0.1`), metric (default: `euclidean`)
  - Metadata table (CSV or TSV) for coloring the plot
  - Color-by column from metadata
  - Random seed (default: `42`)
  - Output directory (default: `./embedding_output`)

## Workflow

1. Read data matrix or precomputed PCA coordinates.
2. If raw data: run PCA first (top 50 PCs) and use PCs as input to embedding (standard practice for large omics datasets).
3. Fit t-SNE or UMAP using specified parameters and random seed.
4. Extract 2D embedding coordinates for each sample/cell.
5. If metadata provided: join embedding coordinates with metadata; generate scatter plot colored by specified column.
6. If no metadata: generate plain scatter plot.
7. Report: number of samples embedded, method and parameters used, runtime.
8. Write embedding coordinates (TSV) and scatter plot (PDF) to output directory.

## Output Contract

- Embedding coordinates (TSV): sample_id, dim1, dim2
- Scatter plot (PDF): 2D embedding colored by metadata or uniform color
- Parameters used (printed to stdout): method, all hyperparameters, random seed

## Limits

- t-SNE and UMAP are non-deterministic (set seed for reproducibility); results vary with hyperparameters.
- t-SNE distances between clusters are not interpretable — use only for local structure visualization.
- UMAP better preserves global structure than t-SNE and is generally faster.
- Both methods are sensitive to the scale of input data; ensure PCA pre-processing for high-dimensional input.
- Common failure: memory error for very large inputs (> 100k cells) — subsample or use approximate UMAP.
