#!/usr/bin/env Rscript

# run_deseq2.R - DESeq2 differential expression analysis pipeline
# Part of the rnaseq-differential-expression skill

suppressPackageStartupMessages({
  library(optparse)
  library(DESeq2)
  library(ggplot2)
  library(pheatmap)
  library(RColorBrewer)
})

# --- Argument parsing ---
option_list <- list(
  make_option("--counts", type = "character", default = NULL,
              help = "Count matrix TSV (gene IDs as rows, samples as columns)"),
  make_option("--quant-dirs", type = "character", default = NULL,
              help = "Quant directory manifest TSV (sample_id<TAB>path), for Salmon/kallisto tximport"),
  make_option("--tx2gene", type = "character", default = NULL,
              help = "Transcript-to-gene TSV (tx_id<TAB>gene_id, no header). Required with --quant-dirs"),
  make_option("--quant-type", type = "character", default = "salmon",
              help = "Quantifier: salmon or kallisto [default: salmon]"),
  make_option("--metadata", type = "character", help = "Sample metadata TSV (sample_id, condition, [batch])"),
  make_option("--contrast", type = "character", default = NULL,
              help = "Contrast: comma-separated condition levels (e.g., treated,control)"),
  make_option("--fdr", type = "double", default = 0.05, help = "FDR threshold [default: 0.05]"),
  make_option("--lfc", type = "double", default = 1, help = "log2 fold-change threshold [default: 1]"),
  make_option("--outdir", type = "character", default = "./de_output",
              help = "Output directory [default: ./de_output]")
)

opt <- parse_args(OptionParser(option_list = option_list))

# Validate: exactly one of --counts or --quant-dirs
counts_mode <- !is.null(opt$counts)
tximport_mode <- !is.null(opt[["quant-dirs"]])

if (!counts_mode && !tximport_mode) {
  stop("Either --counts or --quant-dirs is required.")
}
if (counts_mode && tximport_mode) {
  stop("--counts and --quant-dirs are mutually exclusive.")
}
if (tximport_mode && is.null(opt$tx2gene)) {
  stop("--tx2gene is required when using --quant-dirs.")
}
if (is.null(opt$metadata)) {
  stop("--metadata is required.")
}

dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# --- Read metadata ---
cat("Reading metadata:", opt$metadata, "\n")
meta_data <- read.delim(opt$metadata, check.names = FALSE)
rownames(meta_data) <- meta_data[[1]]
meta_data$condition <- as.factor(meta_data$condition)

# --- Build design formula ---
if ("batch" %in% colnames(meta_data)) {
  meta_data$batch <- as.factor(meta_data$batch)
  design_formula <- ~ batch + condition
  cat("Design formula: ~ batch + condition\n")
} else {
  design_formula <- ~ condition
  cat("Design formula: ~ condition\n")
}

# --- Create DESeqDataSet (count matrix OR tximport path) ---
if (counts_mode) {
  cat("Reading count matrix:", opt$counts, "\n")
  count_data <- read.delim(opt$counts, row.names = 1, check.names = FALSE)

  common_samples <- intersect(colnames(count_data), rownames(meta_data))
  if (length(common_samples) == 0) {
    stop("No matching sample IDs between count matrix columns and metadata rows.")
  }
  cat("Matched samples:", length(common_samples), "\n")

  count_data <- count_data[, common_samples, drop = FALSE]
  meta_data  <- meta_data[common_samples, , drop = FALSE]

  dds <- DESeqDataSetFromMatrix(
    countData = round(as.matrix(count_data)),
    colData   = meta_data,
    design    = design_formula
  )

} else {
  # tximport path: load Salmon / kallisto quant directories
  suppressPackageStartupMessages(library(tximport))

  cat("Reading quant-dirs manifest:", opt[["quant-dirs"]], "\n")
  quant_df <- read.delim(opt[["quant-dirs"]], header = FALSE,
                         col.names = c("sample_id", "quant_path"),
                         stringsAsFactors = FALSE)
  rownames(quant_df) <- quant_df$sample_id

  common_samples <- intersect(quant_df$sample_id, rownames(meta_data))
  if (length(common_samples) == 0) {
    stop("No matching sample IDs between quant-dirs manifest and metadata.")
  }
  cat("Matched samples:", length(common_samples), "\n")

  quant_df  <- quant_df[common_samples, , drop = FALSE]
  meta_data <- meta_data[common_samples, , drop = FALSE]

  # Build named file vector; Salmon: quant.sf, kallisto: abundance.tsv
  if (opt[["quant-type"]] == "salmon") {
    files <- setNames(file.path(quant_df$quant_path, "quant.sf"), common_samples)
  } else {
    files <- setNames(file.path(quant_df$quant_path, "abundance.tsv"), common_samples)
  }

  missing_files <- files[!file.exists(files)]
  if (length(missing_files) > 0) {
    stop("Quant files not found:\n", paste(missing_files, collapse = "\n"))
  }

  cat("Reading tx2gene:", opt$tx2gene, "\n")
  tx2gene <- read.delim(opt$tx2gene, header = FALSE,
                        col.names = c("tx_id", "gene_id"),
                        stringsAsFactors = FALSE)

  cat("Running tximport (type:", opt[["quant-type"]], ")...\n")
  txi <- tximport(files,
                  type     = opt[["quant-type"]],
                  tx2gene  = tx2gene,
                  ignoreTxVersion = TRUE)
  cat("Transcripts imported:", nrow(txi$counts), "→ genes:", nrow(txi$counts), "\n")

  dds <- DESeqDataSetFromTximport(
    txi      = txi,
    colData  = meta_data,
    design   = design_formula
  )
}

# Filter low-count genes
keep <- rowSums(counts(dds)) >= 10
dds <- dds[keep, ]
cat("Genes after filtering:", nrow(dds), "\n")

# --- Run DESeq2 ---
cat("Running DESeq2...\n")
dds <- DESeq(dds)

# --- Extract results ---
if (!is.null(opt$contrast)) {
  contrast_levels <- strsplit(opt$contrast, ",")[[1]]
  if (length(contrast_levels) != 2) {
    stop("Contrast must be two comma-separated condition levels (e.g., treated,control).")
  }
  res <- results(dds, contrast = c("condition", contrast_levels[1], contrast_levels[2]),
                 alpha = opt$fdr)
  cat("Contrast: condition", contrast_levels[1], "vs", contrast_levels[2], "\n")
} else {
  res <- results(dds, alpha = opt$fdr)
  cat("Using default contrast (last vs first level of condition)\n")
}

res_ordered <- res[order(res$padj), ]
res_df <- as.data.frame(res_ordered)
res_df$gene_id <- rownames(res_df)
res_df <- res_df[, c("gene_id", "baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj")]

# --- Summary statistics ---
sig <- res_df[!is.na(res_df$padj) & res_df$padj < opt$fdr & abs(res_df$log2FoldChange) >= opt$lfc, ]
sig_up <- sum(sig$log2FoldChange > 0)
sig_down <- sum(sig$log2FoldChange < 0)

cat("\n=== DESeq2 Results Summary ===\n")
cat("Total genes tested:", nrow(res_df), "\n")
cat("Significant (FDR <", opt$fdr, ", |log2FC| >=", opt$lfc, "):", nrow(sig), "\n")
cat("  Up-regulated:", sig_up, "\n")
cat("  Down-regulated:", sig_down, "\n")

if (nrow(sig) > 0) {
  cat("\nTop hits:\n")
  top_n <- min(10, nrow(sig))
  print(head(sig, top_n))
}

# --- Write results ---
results_file <- file.path(opt$outdir, "de_results.tsv")
write.table(res_df, file = results_file, sep = "\t", row.names = FALSE, quote = FALSE)
cat("\nResults written to:", results_file, "\n")

# --- Write normalized counts ---
norm_counts <- counts(dds, normalized = TRUE)
norm_file <- file.path(opt$outdir, "normalized_counts.tsv")
write.table(data.frame(gene_id = rownames(norm_counts), norm_counts, check.names = FALSE),
            file = norm_file, sep = "\t", row.names = FALSE, quote = FALSE)
cat("Normalized counts written to:", norm_file, "\n")

# --- PCA plot ---
cat("Generating PCA plot...\n")
vsd <- vst(dds, blind = FALSE)

pca_data <- plotPCA(vsd, intgroup = "condition", returnData = TRUE)
pct_var <- round(100 * attr(pca_data, "percentVar"))

pca_plot <- ggplot(pca_data, aes(x = PC1, y = PC2, color = condition)) +
  geom_point(size = 3) +
  xlab(paste0("PC1: ", pct_var[1], "% variance")) +
  ylab(paste0("PC2: ", pct_var[2], "% variance")) +
  ggtitle("PCA of RNA-seq Samples") +
  theme_bw()

pca_file <- file.path(opt$outdir, "pca_plot.pdf")
ggsave(pca_file, pca_plot, width = 7, height = 5)
cat("PCA plot written to:", pca_file, "\n")

# --- Volcano plot ---
cat("Generating volcano plot...\n")
vol_df <- as.data.frame(res)
vol_df$significant <- "NS"
vol_df$significant[!is.na(vol_df$padj) & vol_df$padj < opt$fdr & vol_df$log2FoldChange >= opt$lfc] <- "Up"
vol_df$significant[!is.na(vol_df$padj) & vol_df$padj < opt$fdr & vol_df$log2FoldChange <= -opt$lfc] <- "Down"
vol_df$significant <- factor(vol_df$significant, levels = c("Down", "NS", "Up"))

volcano_plot <- ggplot(vol_df, aes(x = log2FoldChange, y = -log10(pvalue), color = significant)) +
  geom_point(alpha = 0.5, size = 1) +
  scale_color_manual(values = c("Down" = "blue", "NS" = "grey60", "Up" = "red")) +
  geom_vline(xintercept = c(-opt$lfc, opt$lfc), linetype = "dashed", color = "grey40") +
  geom_hline(yintercept = -log10(opt$fdr), linetype = "dashed", color = "grey40") +
  ggtitle("Volcano Plot") +
  xlab("log2 Fold Change") +
  ylab("-log10(p-value)") +
  theme_bw()

volcano_file <- file.path(opt$outdir, "volcano_plot.pdf")
ggsave(volcano_file, volcano_plot, width = 7, height = 5)
cat("Volcano plot written to:", volcano_file, "\n")

# --- MA plot ---
cat("Generating MA plot...\n")
ma_file <- file.path(opt$outdir, "ma_plot.pdf")
pdf(ma_file, width = 7, height = 5)
plotMA(res, main = "MA Plot", ylim = c(-5, 5), alpha = opt$fdr)
dev.off()
cat("MA plot written to:", ma_file, "\n")

# --- Heatmap of top DE genes ---
cat("Generating heatmap...\n")
top_genes <- head(rownames(res_ordered[!is.na(res_ordered$padj) & res_ordered$padj < opt$fdr, ]), 50)

if (length(top_genes) >= 2) {
  heatmap_mat <- assay(vsd)[top_genes, ]
  heatmap_mat <- heatmap_mat - rowMeans(heatmap_mat)

  annotation_col <- data.frame(condition = meta_data$condition, row.names = rownames(meta_data))

  heatmap_file <- file.path(opt$outdir, "heatmap.pdf")
  pdf(heatmap_file, width = 8, height = 10)
  pheatmap(heatmap_mat,
           annotation_col = annotation_col,
           color = colorRampPalette(rev(brewer.pal(n = 7, name = "RdBu")))(100),
           cluster_rows = TRUE,
           cluster_cols = TRUE,
           show_rownames = (length(top_genes) <= 30),
           main = paste("Top", length(top_genes), "DE Genes"))
  dev.off()
  cat("Heatmap written to:", heatmap_file, "\n")
} else {
  cat("Fewer than 2 significant genes; skipping heatmap.\n")
}

# --- Session info ---
session_file <- file.path(opt$outdir, "session_info.txt")
writeLines(capture.output(sessionInfo()), session_file)
cat("Session info written to:", session_file, "\n")

cat("\n=== DESeq2 analysis complete ===\n")
