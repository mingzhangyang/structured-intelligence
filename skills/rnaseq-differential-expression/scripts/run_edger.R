#!/usr/bin/env Rscript

# run_edger.R - edgeR differential expression analysis pipeline
# Part of the rnaseq-differential-expression skill

suppressPackageStartupMessages({
  library(optparse)
  library(edgeR)
  library(ggplot2)
  library(pheatmap)
  library(RColorBrewer)
  library(limma)
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

counts_mode   <- !is.null(opt$counts)
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

# --- Build DGEList (count matrix OR tximport path) ---
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

  dge <- DGEList(counts = as.matrix(count_data), group = meta_data$condition)

  # Filter and normalize
  keep <- filterByExpr(dge, group = meta_data$condition)
  dge  <- dge[keep, , keep.lib.sizes = FALSE]
  cat("Genes after filtering:", nrow(dge), "\n")
  dge  <- calcNormFactors(dge)

} else {
  # tximport path: length-scaled TPM counts for edgeR
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
  # Use lengthScaledTPM for edgeR: corrects for transcript length bias
  txi <- tximport(files,
                  type                = opt[["quant-type"]],
                  tx2gene             = tx2gene,
                  countsFromAbundance = "lengthScaledTPM",
                  ignoreTxVersion     = TRUE)

  cts <- txi$counts
  dge <- DGEList(counts = round(cts), group = meta_data$condition)

  # Incorporate effective-length offset for proper normalization
  norm_mat <- txi$length / exp(rowMeans(log(txi$length)))
  norm_mat <- norm_mat[rownames(dge), colnames(dge)]
  dge      <- scaleOffset(dge, log(norm_mat))

  # Filter and normalize
  keep <- filterByExpr(dge, group = meta_data$condition)
  dge  <- dge[keep, , keep.lib.sizes = FALSE]
  cat("Genes after filtering:", nrow(dge), "\n")
  dge  <- calcNormFactors(dge)
}

# --- Build design matrix ---
if ("batch" %in% colnames(meta_data)) {
  meta_data$batch <- as.factor(meta_data$batch)
  design <- model.matrix(~ batch + condition, data = meta_data)
  cat("Design formula: ~ batch + condition\n")
} else {
  design <- model.matrix(~ condition, data = meta_data)
  cat("Design formula: ~ condition\n")
}

# --- Estimate dispersion and fit ---
cat("Estimating dispersion...\n")
dge <- estimateDisp(dge, design)

cat("Fitting GLM...\n")
fit <- glmQLFit(dge, design)

# --- Determine contrast coefficient ---
if (!is.null(opt$contrast)) {
  contrast_levels <- strsplit(opt$contrast, ",")[[1]]
  if (length(contrast_levels) != 2) {
    stop("Contrast must be two comma-separated condition levels (e.g., treated,control).")
  }
  # Find the coefficient for the numerator condition
  coef_name <- paste0("condition", contrast_levels[1])
  if (!(coef_name %in% colnames(design))) {
    # Try to find it in the design matrix columns
    coef_candidates <- grep("^condition", colnames(design), value = TRUE)
    stop(paste("Coefficient", coef_name, "not found in design. Available:",
               paste(coef_candidates, collapse = ", ")))
  }
  cat("Contrast: condition", contrast_levels[1], "vs", contrast_levels[2], "\n")
  qlf <- glmQLFTest(fit, coef = coef_name)
} else {
  # Default: last coefficient
  qlf <- glmQLFTest(fit, coef = ncol(design))
  cat("Using default contrast (last coefficient in design matrix)\n")
}

# --- Extract results ---
res <- topTags(qlf, n = Inf, sort.by = "PValue")$table
res$gene_id <- rownames(res)
res <- res[, c("gene_id", "logFC", "logCPM", "F", "PValue", "FDR")]

# --- Summary statistics ---
sig <- res[!is.na(res$FDR) & res$FDR < opt$fdr & abs(res$logFC) >= opt$lfc, ]
sig_up <- sum(sig$logFC > 0)
sig_down <- sum(sig$logFC < 0)

cat("\n=== edgeR Results Summary ===\n")
cat("Total genes tested:", nrow(res), "\n")
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
write.table(res, file = results_file, sep = "\t", row.names = FALSE, quote = FALSE)
cat("\nResults written to:", results_file, "\n")

# --- Write normalized counts (CPM) ---
norm_counts <- cpm(dge, normalized.lib.sizes = TRUE)
norm_file <- file.path(opt$outdir, "normalized_counts.tsv")
write.table(data.frame(gene_id = rownames(norm_counts), norm_counts, check.names = FALSE),
            file = norm_file, sep = "\t", row.names = FALSE, quote = FALSE)
cat("Normalized counts (CPM) written to:", norm_file, "\n")

# --- PCA plot (using logCPM) ---
cat("Generating PCA plot...\n")
logcpm <- cpm(dge, log = TRUE, prior.count = 2)
pca_result <- prcomp(t(logcpm), center = TRUE, scale. = FALSE)
pct_var <- round(100 * (pca_result$sdev^2 / sum(pca_result$sdev^2)))

pca_data <- data.frame(
  PC1 = pca_result$x[, 1],
  PC2 = pca_result$x[, 2],
  condition = meta_data$condition,
  sample = rownames(meta_data)
)

pca_plot <- ggplot(pca_data, aes(x = PC1, y = PC2, color = condition)) +
  geom_point(size = 3) +
  xlab(paste0("PC1: ", pct_var[1], "% variance")) +
  ylab(paste0("PC2: ", pct_var[2], "% variance")) +
  ggtitle("PCA of RNA-seq Samples (edgeR logCPM)") +
  theme_bw()

pca_file <- file.path(opt$outdir, "pca_plot.pdf")
ggsave(pca_file, pca_plot, width = 7, height = 5)
cat("PCA plot written to:", pca_file, "\n")

# --- Volcano plot ---
cat("Generating volcano plot...\n")
vol_df <- res
vol_df$significant <- "NS"
vol_df$significant[!is.na(vol_df$FDR) & vol_df$FDR < opt$fdr & vol_df$logFC >= opt$lfc] <- "Up"
vol_df$significant[!is.na(vol_df$FDR) & vol_df$FDR < opt$fdr & vol_df$logFC <= -opt$lfc] <- "Down"
vol_df$significant <- factor(vol_df$significant, levels = c("Down", "NS", "Up"))

volcano_plot <- ggplot(vol_df, aes(x = logFC, y = -log10(PValue), color = significant)) +
  geom_point(alpha = 0.5, size = 1) +
  scale_color_manual(values = c("Down" = "blue", "NS" = "grey60", "Up" = "red")) +
  geom_vline(xintercept = c(-opt$lfc, opt$lfc), linetype = "dashed", color = "grey40") +
  geom_hline(yintercept = -log10(opt$fdr), linetype = "dashed", color = "grey40") +
  ggtitle("Volcano Plot (edgeR)") +
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
plotMD(qlf, main = "MA Plot (edgeR)")
abline(h = c(-opt$lfc, opt$lfc), col = "blue", lty = 2)
dev.off()
cat("MA plot written to:", ma_file, "\n")

# --- Heatmap of top DE genes ---
cat("Generating heatmap...\n")
sig_genes <- rownames(res[!is.na(res$FDR) & res$FDR < opt$fdr, ])
top_genes <- head(sig_genes, 50)

if (length(top_genes) >= 2) {
  heatmap_mat <- logcpm[top_genes, ]
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
           main = paste("Top", length(top_genes), "DE Genes (edgeR)"))
  dev.off()
  cat("Heatmap written to:", heatmap_file, "\n")
} else {
  cat("Fewer than 2 significant genes; skipping heatmap.\n")
}

# --- Session info ---
session_file <- file.path(opt$outdir, "session_info.txt")
writeLines(capture.output(sessionInfo()), session_file)
cat("Session info written to:", session_file, "\n")

cat("\n=== edgeR analysis complete ===\n")
