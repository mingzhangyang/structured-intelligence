---
name: stat-cluster-samples
description: Cluster samples or features using k-means or hierarchical clustering, evaluate cluster quality with silhouette scores, and produce a dendrogram or cluster plot.
---

# Skill: Sample Clustering

## Use When

- User wants to discover groups of similar samples or features in high-dimensional data
- User wants to create a heatmap with hierarchical clustering of genes and samples
- User wants to determine the optimal number of clusters for k-means
- Use cases: gene expression pattern discovery, cell type grouping, patient stratification

## Inputs

- Required:
  - Data matrix (CSV or TSV): rows = samples (or features), columns = features (or samples)
- Optional:
  - Matrix orientation: `samples_as_rows` (default) or `samples_as_columns`
  - Clustering method: `hierarchical` (default) or `kmeans`
  - For hierarchical: linkage method (`ward` default, `complete`, `average`, `single`)
  - Distance metric: `euclidean` (default), `correlation`, or `cosine`
  - For k-means: number of clusters k (default: auto-select using elbow method, k = 2–10)
  - Scale features before clustering: `true` (default) or `false`
  - Metadata table for heatmap annotation (optional)
  - Output directory (default: `./cluster_output`)

## Workflow

1. Read data matrix; scale features if requested.
2. If hierarchical clustering:
   a. Compute distance matrix using specified metric.
   b. Perform hierarchical clustering on both rows (samples) and columns (features).
   c. Generate a clustered heatmap with dendrogram.
3. If k-means:
   a. If k not specified: compute within-cluster sum of squares for k = 2–10; plot elbow curve; select k at elbow.
   b. Fit k-means with selected k; report cluster assignments.
   c. Generate PCA-based cluster scatter plot.
4. Compute silhouette score for final cluster solution; report mean and per-sample scores.
5. Assign and report cluster labels for each sample.
6. Write cluster assignments (TSV), silhouette scores (TSV), heatmap or cluster plot (PDF) to output directory.

## Output Contract

- Cluster assignments table (TSV): sample_id, cluster_label
- Silhouette scores table (TSV): sample_id, silhouette_score, cluster_label
- Clustered heatmap (PDF, hierarchical) or cluster scatter plot (PDF, k-means)
- Elbow curve (PDF, k-means only when k is auto-selected)
- Mean silhouette score (printed to stdout)

## Limits

- K-means assumes spherical, similarly sized clusters; performs poorly on elongated or irregular shapes.
- Hierarchical clustering with Ward linkage and Euclidean distance is sensitive to outliers; remove outliers before clustering.
- Very large matrices (> 10k samples or > 50k features) may be slow; consider subsampling or running PCA first.
- Common failure: data with many zero entries (e.g., single-cell) — apply dimensionality reduction first.
