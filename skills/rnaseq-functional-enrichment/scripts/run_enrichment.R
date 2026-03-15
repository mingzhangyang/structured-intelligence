#!/usr/bin/env Rscript

# run_enrichment.R - GO, KEGG, and Reactome functional enrichment analysis
# Part of the rnaseq-functional-enrichment skill
# Supports ORA (over-representation analysis) and GSEA (gene set enrichment analysis)
# via clusterProfiler, with optional Reactome via ReactomePA.

suppressPackageStartupMessages({
  library(optparse)
  library(clusterProfiler)
  library(enrichplot)
  library(ggplot2)
})

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
option_list <- list(
  make_option("--de-results",   type = "character", default = NULL,
              help = "DE results TSV (columns: gene_id, log2FoldChange, padj)"),
  make_option("--ranked-list",  type = "character", default = NULL,
              help = "Pre-ranked gene list TSV (columns: gene_id, score)"),
  make_option("--analysis",     type = "character", default = "ora",
              help = "Analysis type: ora or gsea [default: ora]"),
  make_option("--organism",     type = "character", default = "hsa",
              help = "KEGG organism code: hsa, mmu, rno, dre [default: hsa]"),
  make_option("--gene-id-type", type = "character", default = "SYMBOL",
              help = "Gene ID type: SYMBOL, ENSEMBL, or ENTREZID [default: SYMBOL]"),
  make_option("--databases",    type = "character", default = "go,kegg",
              help = "Comma-separated databases: go,kegg,reactome [default: go,kegg]"),
  make_option("--fdr",          type = "double",    default = 0.05,
              help = "FDR threshold for ORA gene filtering and result cutoff [default: 0.05]"),
  make_option("--min-gs-size",  type = "integer",   default = 5L,
              help = "Minimum gene set size [default: 5]"),
  make_option("--max-gs-size",  type = "integer",   default = 500L,
              help = "Maximum gene set size [default: 500]"),
  make_option("--outdir",       type = "character", default = "enrichment_results",
              help = "Output directory [default: enrichment_results]")
)

opt <- parse_args(OptionParser(option_list = option_list))

# Validate mutually exclusive inputs
if (is.null(opt[["de-results"]]) && is.null(opt[["ranked-list"]])) {
  stop("One of --de-results or --ranked-list is required.")
}
if (!is.null(opt[["de-results"]]) && !is.null(opt[["ranked-list"]])) {
  stop("--de-results and --ranked-list are mutually exclusive.")
}

dir.create(opt$outdir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Organism → OrgDb mapping
# ---------------------------------------------------------------------------
org_db_map <- list(
  hsa = "org.Hs.eg.db",
  mmu = "org.Mm.eg.db",
  rno = "org.Rn.eg.db",
  dre = "org.Dr.eg.db"
)

org_db_name <- org_db_map[[opt$organism]]
if (is.null(org_db_name)) {
  stop(sprintf("Unsupported organism '%s'. Supported: hsa, mmu, rno, dre.", opt$organism))
}

if (!requireNamespace(org_db_name, quietly = TRUE)) {
  stop(sprintf("OrgDb package '%s' is not installed. Install with: BiocManager::install('%s')",
               org_db_name, org_db_name))
}
org_db <- get(org_db_name, envir = asNamespace(org_db_name))

# Parse requested databases
databases <- tolower(trimws(strsplit(opt$databases, ",")[[1]]))
use_go       <- "go"       %in% databases
use_kegg     <- "kegg"     %in% databases
use_reactome <- "reactome" %in% databases

if (use_reactome && !requireNamespace("ReactomePA", quietly = TRUE)) {
  warning("ReactomePA is not installed; skipping Reactome analysis. Install with: BiocManager::install('ReactomePA')")
  use_reactome <- FALSE
}

# ---------------------------------------------------------------------------
# Helper: strip Ensembl version suffixes (ENSG00000123.5 → ENSG00000123)
# ---------------------------------------------------------------------------
strip_ensembl_version <- function(ids) {
  sub("\\.\\d+$", "", ids)
}

# ---------------------------------------------------------------------------
# Helper: convert gene IDs to ENTREZID using bitr()
# ---------------------------------------------------------------------------
convert_ids <- function(gene_ids, from_type, org_db) {
  if (from_type == "ENSEMBL") {
    gene_ids <- strip_ensembl_version(gene_ids)
  }
  if (from_type == "ENTREZID") {
    return(data.frame(original = gene_ids, ENTREZID = gene_ids, stringsAsFactors = FALSE))
  }
  tryCatch({
    mapped <- bitr(gene_ids, fromType = from_type, toType = "ENTREZID", OrgDb = org_db)
    colnames(mapped)[colnames(mapped) == from_type] <- "original"
    # Deduplicate: keep one Entrez ID per original ID
    mapped <- mapped[!duplicated(mapped$original), ]
    mapped
  }, error = function(e) {
    stop(sprintf("Gene ID conversion failed: %s", conditionMessage(e)))
  })
}

# ---------------------------------------------------------------------------
# Helper: save enrichment table TSV
# ---------------------------------------------------------------------------
save_table <- function(result_obj, path, label) {
  if (is.null(result_obj) || nrow(as.data.frame(result_obj)) == 0) {
    cat(sprintf("  No significant results for %s; skipping table.\n", label))
    return(invisible(NULL))
  }
  df <- as.data.frame(result_obj)
  write.table(df, file = path, sep = "\t", row.names = FALSE, quote = FALSE)
  cat(sprintf("  %s table written to: %s (%d terms)\n", label, path, nrow(df)))
}

# ---------------------------------------------------------------------------
# Helper: save dotplot PDF
# ---------------------------------------------------------------------------
save_dotplot <- function(result_obj, path, title, top_n = 20) {
  if (is.null(result_obj) || nrow(as.data.frame(result_obj)) == 0) {
    cat(sprintf("  Skipping dotplot for %s (no results).\n", title))
    return(invisible(NULL))
  }
  tryCatch({
    p <- dotplot(result_obj, showCategory = top_n, title = title) + theme_bw()
    ggsave(path, p, width = 8, height = 7)
    cat(sprintf("  Dotplot written to: %s\n", path))
  }, error = function(e) {
    warning(sprintf("Dotplot failed for %s: %s", title, conditionMessage(e)))
  })
}

# ---------------------------------------------------------------------------
# Helper: save barplot PDF
# ---------------------------------------------------------------------------
save_barplot <- function(result_obj, path, title, top_n = 20) {
  if (is.null(result_obj) || nrow(as.data.frame(result_obj)) == 0) {
    cat(sprintf("  Skipping barplot for %s (no results).\n", title))
    return(invisible(NULL))
  }
  tryCatch({
    p <- barplot(result_obj, showCategory = top_n, title = title) + theme_bw()
    ggsave(path, p, width = 9, height = 7)
    cat(sprintf("  Barplot written to: %s\n", path))
  }, error = function(e) {
    warning(sprintf("Barplot failed for %s: %s", title, conditionMessage(e)))
  })
}

# ---------------------------------------------------------------------------
# Helper: save emapplot (enrichment map) PDF
# ---------------------------------------------------------------------------
save_emapplot <- function(result_obj, path, title, top_n = 30) {
  if (is.null(result_obj) || nrow(as.data.frame(result_obj)) < 2) {
    cat(sprintf("  Skipping emapplot for %s (fewer than 2 terms).\n", title))
    return(invisible(NULL))
  }
  tryCatch({
    result_obj <- pairwise_termsim(result_obj)
    p <- emapplot(result_obj, showCategory = top_n) +
      ggtitle(title) +
      theme(plot.title = element_text(hjust = 0.5))
    ggsave(path, p, width = 10, height = 8)
    cat(sprintf("  Emapplot written to: %s\n", path))
  }, error = function(e) {
    warning(sprintf("Emapplot failed for %s: %s", title, conditionMessage(e)))
  })
}

# ---------------------------------------------------------------------------
# Helper: save cnetplot PDF
# ---------------------------------------------------------------------------
save_cnetplot <- function(result_obj, gene_list, path, title, top_n = 10) {
  if (is.null(result_obj) || nrow(as.data.frame(result_obj)) == 0) {
    cat(sprintf("  Skipping cnetplot for %s (no results).\n", title))
    return(invisible(NULL))
  }
  tryCatch({
    p <- cnetplot(result_obj, showCategory = top_n, foldChange = gene_list,
                  colorEdge = TRUE) +
      ggtitle(title) +
      theme(plot.title = element_text(hjust = 0.5))
    ggsave(path, p, width = 11, height = 9)
    cat(sprintf("  Cnetplot written to: %s\n", path))
  }, error = function(e) {
    warning(sprintf("Cnetplot failed for %s: %s", title, conditionMessage(e)))
  })
}

# ---------------------------------------------------------------------------
# Helper: print top N results summary
# ---------------------------------------------------------------------------
print_top_results <- function(result_obj, label, n = 10) {
  df <- tryCatch(as.data.frame(result_obj), error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) {
    cat(sprintf("  %s: no significant results.\n", label))
    return(invisible(NULL))
  }
  cat(sprintf("\n  Top %s results (%s):\n", min(n, nrow(df)), label))
  top_df <- head(df[, c("ID", "Description", "p.adjust"), drop = FALSE], n)
  for (i in seq_len(nrow(top_df))) {
    cat(sprintf("    [%s] %s (FDR=%.3g)\n",
                top_df$ID[i], top_df$Description[i], top_df$p.adjust[i]))
  }
}

# ===========================================================================
# ORA workflow
# ===========================================================================
run_ora <- function(opt, org_db, use_go, use_kegg, use_reactome) {
  cat("=== Over-Representation Analysis (ORA) ===\n\n")

  # Read DE results
  cat("Reading DE results:", opt[["de-results"]], "\n")
  de <- read.delim(opt[["de-results"]], check.names = FALSE, stringsAsFactors = FALSE)

  required_cols <- c("gene_id", "padj")
  missing_cols  <- setdiff(required_cols, colnames(de))
  if (length(missing_cols) > 0) {
    stop(sprintf("DE results table missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))
  }

  cat(sprintf("Total genes in DE table: %d\n", nrow(de)))

  # Filter significant genes for ORA
  sig_de <- de[!is.na(de$padj) & de$padj < opt$fdr, ]
  cat(sprintf("Significant genes (padj < %g): %d\n", opt$fdr, nrow(sig_de)))

  if (nrow(sig_de) == 0) {
    stop(sprintf("No genes pass the FDR threshold of %g. Consider relaxing --fdr.", opt$fdr))
  }

  # Convert IDs
  cat("\nConverting gene IDs to ENTREZID...\n")
  id_map_sig  <- convert_ids(sig_de$gene_id,  opt[["gene-id-type"]], org_db)
  id_map_all  <- convert_ids(de$gene_id,       opt[["gene-id-type"]], org_db)
  sig_entrez  <- unique(id_map_sig$ENTREZID)
  all_entrez  <- unique(id_map_all$ENTREZID)
  cat(sprintf("Significant genes with ENTREZID: %d / %d\n", length(sig_entrez), nrow(sig_de)))
  cat(sprintf("Background genes with ENTREZID:  %d / %d\n", length(all_entrez), nrow(de)))

  # ---- GO enrichment ----
  go_bp <- go_cc <- go_mf <- NULL
  if (use_go) {
    cat("\n--- GO Biological Process ---\n")
    go_bp <- tryCatch(
      enrichGO(gene          = sig_entrez,
               universe      = all_entrez,
               OrgDb         = org_db,
               ont           = "BP",
               pAdjustMethod = "BH",
               pvalueCutoff  = opt$fdr,
               qvalueCutoff  = opt$fdr,
               minGSSize     = opt[["min-gs-size"]],
               maxGSSize     = opt[["max-gs-size"]],
               readable      = TRUE),
      error = function(e) { warning(sprintf("GO BP failed: %s", conditionMessage(e))); NULL }
    )
    save_table(go_bp,
               file.path(opt$outdir, "go_bp_enrichment.tsv"),
               "GO BP")
    print_top_results(go_bp, "GO BP")

    cat("\n--- GO Cellular Component ---\n")
    go_cc <- tryCatch(
      enrichGO(gene          = sig_entrez,
               universe      = all_entrez,
               OrgDb         = org_db,
               ont           = "CC",
               pAdjustMethod = "BH",
               pvalueCutoff  = opt$fdr,
               qvalueCutoff  = opt$fdr,
               minGSSize     = opt[["min-gs-size"]],
               maxGSSize     = opt[["max-gs-size"]],
               readable      = TRUE),
      error = function(e) { warning(sprintf("GO CC failed: %s", conditionMessage(e))); NULL }
    )
    save_table(go_cc,
               file.path(opt$outdir, "go_cc_enrichment.tsv"),
               "GO CC")
    print_top_results(go_cc, "GO CC")

    cat("\n--- GO Molecular Function ---\n")
    go_mf <- tryCatch(
      enrichGO(gene          = sig_entrez,
               universe      = all_entrez,
               OrgDb         = org_db,
               ont           = "MF",
               pAdjustMethod = "BH",
               pvalueCutoff  = opt$fdr,
               qvalueCutoff  = opt$fdr,
               minGSSize     = opt[["min-gs-size"]],
               maxGSSize     = opt[["max-gs-size"]],
               readable      = TRUE),
      error = function(e) { warning(sprintf("GO MF failed: %s", conditionMessage(e))); NULL }
    )
    save_table(go_mf,
               file.path(opt$outdir, "go_mf_enrichment.tsv"),
               "GO MF")
    print_top_results(go_mf, "GO MF")

    # GO plots
    cat("\n--- Generating GO plots ---\n")
    save_dotplot(go_bp, file.path(opt$outdir, "go_bp_dotplot.pdf"), "GO BP (ORA) - Top 20", 20)
    save_dotplot(go_cc, file.path(opt$outdir, "go_cc_dotplot.pdf"), "GO CC (ORA) - Top 20", 20)
    save_dotplot(go_mf, file.path(opt$outdir, "go_mf_dotplot.pdf"), "GO MF (ORA) - Top 20", 20)
    save_emapplot(go_bp, file.path(opt$outdir, "go_bp_emapplot.pdf"), "GO BP Enrichment Map")
    save_cnetplot(go_bp, NULL, file.path(opt$outdir, "go_bp_cnetplot.pdf"), "GO BP Gene-Concept Network")
  }

  # ---- KEGG enrichment ----
  kegg_res <- NULL
  if (use_kegg) {
    cat("\n--- KEGG Pathway ---\n")
    kegg_res <- tryCatch(
      enrichKEGG(gene          = sig_entrez,
                 universe      = all_entrez,
                 organism      = opt$organism,
                 pAdjustMethod = "BH",
                 pvalueCutoff  = opt$fdr,
                 qvalueCutoff  = opt$fdr,
                 minGSSize     = opt[["min-gs-size"]],
                 maxGSSize     = opt[["max-gs-size"]]),
      error = function(e) { warning(sprintf("KEGG failed: %s", conditionMessage(e))); NULL }
    )
    save_table(kegg_res,
               file.path(opt$outdir, "kegg_enrichment.tsv"),
               "KEGG")
    print_top_results(kegg_res, "KEGG")

    cat("\n--- Generating KEGG plots ---\n")
    save_barplot(kegg_res,  file.path(opt$outdir, "kegg_barplot.pdf"),  "KEGG Pathways (ORA) - Top 20", 20)
    save_emapplot(kegg_res, file.path(opt$outdir, "kegg_emapplot.pdf"), "KEGG Enrichment Map")
    save_cnetplot(kegg_res, NULL, file.path(opt$outdir, "kegg_cnetplot.pdf"), "KEGG Gene-Concept Network")
  }

  # ---- Reactome enrichment ----
  if (use_reactome) {
    suppressPackageStartupMessages(library(ReactomePA))
    cat("\n--- Reactome Pathway ---\n")
    reactome_res <- tryCatch(
      enrichPathway(gene          = sig_entrez,
                    universe      = all_entrez,
                    organism      = switch(opt$organism,
                                          hsa = "human",
                                          mmu = "mouse",
                                          rno = "rat",
                                          dre = "zebrafish"),
                    pAdjustMethod = "BH",
                    pvalueCutoff  = opt$fdr,
                    qvalueCutoff  = opt$fdr,
                    minGSSize     = opt[["min-gs-size"]],
                    maxGSSize     = opt[["max-gs-size"]],
                    readable      = TRUE),
      error = function(e) { warning(sprintf("Reactome failed: %s", conditionMessage(e))); NULL }
    )
    save_table(reactome_res,
               file.path(opt$outdir, "reactome_enrichment.tsv"),
               "Reactome")
    print_top_results(reactome_res, "Reactome")

    cat("\n--- Generating Reactome plots ---\n")
    save_dotplot(reactome_res,  file.path(opt$outdir, "reactome_dotplot.pdf"),  "Reactome Pathways (ORA) - Top 20", 20)
    save_emapplot(reactome_res, file.path(opt$outdir, "reactome_emapplot.pdf"), "Reactome Enrichment Map")
  }
}

# ===========================================================================
# GSEA workflow
# ===========================================================================
run_gsea <- function(opt, org_db, use_go, use_kegg, use_reactome) {
  cat("=== Gene Set Enrichment Analysis (GSEA) ===\n\n")

  # Build ranked gene list
  if (!is.null(opt[["ranked-list"]])) {
    cat("Reading pre-ranked gene list:", opt[["ranked-list"]], "\n")
    rl <- read.delim(opt[["ranked-list"]], check.names = FALSE, stringsAsFactors = FALSE)
    if (!all(c("gene_id", "score") %in% colnames(rl))) {
      stop("Ranked list must have columns: gene_id, score")
    }
    gene_ids <- rl$gene_id
    scores   <- rl$score
  } else {
    cat("Reading DE results and computing ranks:", opt[["de-results"]], "\n")
    de <- read.delim(opt[["de-results"]], check.names = FALSE, stringsAsFactors = FALSE)
    required_cols <- c("gene_id", "log2FoldChange", "padj")
    missing_cols  <- setdiff(required_cols, colnames(de))
    if (length(missing_cols) > 0) {
      stop(sprintf("DE results table missing required columns for GSEA: %s",
                   paste(missing_cols, collapse = ", ")))
    }
    # Ranking metric: -log10(padj) * sign(log2FoldChange)
    # Use a small floor for padj to avoid Inf
    padj_floor <- pmax(de$padj, 1e-300)
    scores  <- -log10(padj_floor) * sign(de$log2FoldChange)
    gene_ids <- de$gene_id
    # Remove NA rankings
    valid <- !is.na(scores) & !is.na(gene_ids)
    gene_ids <- gene_ids[valid]
    scores   <- scores[valid]
    cat(sprintf("Genes with valid ranking scores: %d\n", length(gene_ids)))
  }

  # Convert IDs
  cat("\nConverting gene IDs to ENTREZID...\n")
  id_map <- convert_ids(gene_ids, opt[["gene-id-type"]], org_db)

  # Build named numeric vector; keep highest-score duplicate per gene
  merged_df <- data.frame(
    gene_id  = gene_ids,
    score    = scores,
    stringsAsFactors = FALSE
  )
  merged_df <- merge(merged_df, id_map, by.x = "gene_id", by.y = "original", all.x = FALSE)
  # Keep one entry per ENTREZID (highest absolute score)
  merged_df <- merged_df[order(abs(merged_df$score), decreasing = TRUE), ]
  merged_df <- merged_df[!duplicated(merged_df$ENTREZID), ]

  gene_list <- setNames(merged_df$score, merged_df$ENTREZID)
  gene_list <- sort(gene_list, decreasing = TRUE)
  cat(sprintf("Genes in ranked list after ID conversion: %d\n", length(gene_list)))

  if (length(gene_list) < 10) {
    stop("Fewer than 10 genes with valid ENTREZID mapping; cannot run GSEA.")
  }

  # ---- GO GSEA ----
  gsea_go_bp <- NULL
  if (use_go) {
    cat("\n--- GSEA: GO Biological Process ---\n")
    gsea_go_bp <- tryCatch(
      gseGO(geneList      = gene_list,
            OrgDb         = org_db,
            ont           = "BP",
            nPerm         = 1000,
            minGSSize     = opt[["min-gs-size"]],
            maxGSSize     = opt[["max-gs-size"]],
            pvalueCutoff  = opt$fdr,
            pAdjustMethod = "BH",
            verbose       = FALSE),
      error = function(e) { warning(sprintf("GSEA GO BP failed: %s", conditionMessage(e))); NULL }
    )
    save_table(gsea_go_bp,
               file.path(opt$outdir, "gsea_go_bp_results.tsv"),
               "GSEA GO BP")
    print_top_results(gsea_go_bp, "GSEA GO BP")

    cat("\n--- Generating GSEA GO plots ---\n")
    save_dotplot(gsea_go_bp, file.path(opt$outdir, "gsea_go_bp_dotplot.pdf"),
                 "GSEA GO BP - Top 20", 20)
    save_emapplot(gsea_go_bp, file.path(opt$outdir, "gsea_go_bp_emapplot.pdf"),
                  "GSEA GO BP Enrichment Map")

    # Ridge plot of top GO BP terms
    if (!is.null(gsea_go_bp) && nrow(as.data.frame(gsea_go_bp)) > 0) {
      tryCatch({
        p_ridge <- ridgeplot(gsea_go_bp, showCategory = 20) +
          ggtitle("GSEA GO BP - Density of Core Enrichment Genes") +
          theme_bw()
        ggsave(file.path(opt$outdir, "gsea_go_bp_ridgeplot.pdf"), p_ridge, width = 10, height = 8)
        cat("  Ridge plot written to:", file.path(opt$outdir, "gsea_go_bp_ridgeplot.pdf"), "\n")
      }, error = function(e) {
        warning(sprintf("Ridge plot failed: %s", conditionMessage(e)))
      })
    }
  }

  # ---- KEGG GSEA ----
  gsea_kegg <- NULL
  if (use_kegg) {
    cat("\n--- GSEA: KEGG Pathway ---\n")
    gsea_kegg <- tryCatch(
      gseKEGG(geneList      = gene_list,
              organism      = opt$organism,
              nPerm         = 1000,
              minGSSize     = opt[["min-gs-size"]],
              maxGSSize     = opt[["max-gs-size"]],
              pvalueCutoff  = opt$fdr,
              pAdjustMethod = "BH",
              verbose       = FALSE),
      error = function(e) { warning(sprintf("GSEA KEGG failed: %s", conditionMessage(e))); NULL }
    )
    save_table(gsea_kegg,
               file.path(opt$outdir, "gsea_kegg_results.tsv"),
               "GSEA KEGG")
    print_top_results(gsea_kegg, "GSEA KEGG")

    cat("\n--- Generating GSEA KEGG plots ---\n")
    save_dotplot(gsea_kegg,  file.path(opt$outdir, "gsea_kegg_dotplot.pdf"),  "GSEA KEGG - Top 20", 20)
    save_emapplot(gsea_kegg, file.path(opt$outdir, "gsea_kegg_emapplot.pdf"), "GSEA KEGG Enrichment Map")

    # GSEA enrichment score plot for top KEGG pathway
    if (!is.null(gsea_kegg) && nrow(as.data.frame(gsea_kegg)) > 0) {
      tryCatch({
        top_pathway_id <- as.data.frame(gsea_kegg)$ID[1]
        p_gsea <- gseaplot2(gsea_kegg, geneSetID = top_pathway_id,
                            title = sprintf("GSEA: %s", top_pathway_id))
        ggsave(file.path(opt$outdir, "gsea_kegg_top_pathway.pdf"), p_gsea, width = 9, height = 6)
        cat("  GSEA enrichment plot written to:",
            file.path(opt$outdir, "gsea_kegg_top_pathway.pdf"), "\n")
      }, error = function(e) {
        warning(sprintf("GSEA enrichment score plot failed: %s", conditionMessage(e)))
      })
    }
  }

  # ---- Reactome GSEA ----
  if (use_reactome) {
    suppressPackageStartupMessages(library(ReactomePA))
    cat("\n--- GSEA: Reactome Pathway ---\n")
    reactome_organism <- switch(opt$organism,
                                hsa = "human",
                                mmu = "mouse",
                                rno = "rat",
                                dre = "zebrafish")
    gsea_reactome <- tryCatch(
      gsePathway(geneList      = gene_list,
                 organism      = reactome_organism,
                 nPerm         = 1000,
                 minGSSize     = opt[["min-gs-size"]],
                 maxGSSize     = opt[["max-gs-size"]],
                 pvalueCutoff  = opt$fdr,
                 pAdjustMethod = "BH",
                 verbose       = FALSE),
      error = function(e) { warning(sprintf("GSEA Reactome failed: %s", conditionMessage(e))); NULL }
    )
    save_table(gsea_reactome,
               file.path(opt$outdir, "gsea_reactome_results.tsv"),
               "GSEA Reactome")
    print_top_results(gsea_reactome, "GSEA Reactome")

    cat("\n--- Generating GSEA Reactome plots ---\n")
    save_dotplot(gsea_reactome,  file.path(opt$outdir, "gsea_reactome_dotplot.pdf"),
                 "GSEA Reactome - Top 20", 20)
    save_emapplot(gsea_reactome, file.path(opt$outdir, "gsea_reactome_emapplot.pdf"),
                  "GSEA Reactome Enrichment Map")
  }
}

# ===========================================================================
# Main dispatch
# ===========================================================================
cat(sprintf("Analysis:      %s\n",  opt$analysis))
cat(sprintf("Organism:      %s\n",  opt$organism))
cat(sprintf("Gene ID type:  %s\n",  opt[["gene-id-type"]]))
cat(sprintf("Databases:     %s\n",  opt$databases))
cat(sprintf("FDR cutoff:    %g\n",  opt$fdr))
cat(sprintf("Gene set size: %d – %d\n", opt[["min-gs-size"]], opt[["max-gs-size"]]))
cat(sprintf("Output dir:    %s\n\n", opt$outdir))

if (opt$analysis == "ora") {
  run_ora(opt, org_db, use_go, use_kegg, use_reactome)
} else if (opt$analysis == "gsea") {
  run_gsea(opt, org_db, use_go, use_kegg, use_reactome)
} else {
  stop(sprintf("Unknown analysis type '%s'. Use 'ora' or 'gsea'.", opt$analysis))
}

# ---------------------------------------------------------------------------
# Session info
# ---------------------------------------------------------------------------
session_file <- file.path(opt$outdir, "session_info.txt")
writeLines(capture.output(sessionInfo()), session_file)
cat(sprintf("\nSession info written to: %s\n", session_file))

cat("\n=== Functional enrichment analysis complete ===\n")
