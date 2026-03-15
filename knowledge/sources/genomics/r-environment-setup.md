---
name: genomics-r-environment-setup
description: Instructions for setting up R and Bioconductor environments for RNA-seq differential expression and functional enrichment analysis.
---

# R / Bioconductor Environment Setup

## R Installation

### System R (recommended for reproducibility)

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y r-base r-base-dev libcurl4-openssl-dev libssl-dev libxml2-dev

# CentOS/RHEL
sudo yum install -y R R-devel libcurl-devel openssl-devel libxml2-devel
```

### Conda (alternative)

```bash
conda create -n rnaseq r-base=4.3 r-essentials bioconductor-deseq2 bioconductor-edger -c conda-forge -c bioconda
conda activate rnaseq
```

## Bioconductor Package Installation

```r
# Install BiocManager
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

# Core differential expression
BiocManager::install(c(
    "DESeq2",
    "edgeR",
    "limma"
))

# Annotation and enrichment (optional, for future functional-enrichment skill)
BiocManager::install(c(
    "clusterProfiler",
    "org.Hs.eg.db",
    "AnnotationDbi",
    "enrichplot",
    "pathview"
))

# Utilities
install.packages(c(
    "tidyverse",
    "pheatmap",
    "RColorBrewer",
    "optparse",
    "jsonlite"
))
```

## Version Verification

```r
# Check installed versions
sessionInfo()
packageVersion("DESeq2")    # expect >= 1.40
packageVersion("edgeR")     # expect >= 3.42
packageVersion("limma")     # expect >= 3.56
```

## Rscript Invocation Pattern

Skills that use R follow this pattern:

```bash
# In scripts/run.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Rscript --vanilla "$SCRIPT_DIR/run_deseq2.R" "$@"
```

The `--vanilla` flag ensures no user `.Rprofile` or `.RData` interfere with reproducibility.

## Python Alternatives

For environments where R is unavailable:

| R Package | Python Alternative | Install |
|-----------|-------------------|---------|
| DESeq2 | PyDESeq2 | `pip install pydeseq2` |
| edgeR | — | No direct equivalent |
| clusterProfiler | gseapy | `pip install gseapy` |
| pheatmap | seaborn clustermap | `pip install seaborn` |
