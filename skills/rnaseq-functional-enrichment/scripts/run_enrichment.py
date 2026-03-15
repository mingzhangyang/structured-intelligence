#!/usr/bin/env python3
"""
run_enrichment.py - GO, KEGG, and Reactome functional enrichment analysis via gseapy.
Part of the rnaseq-functional-enrichment skill.

Supports:
  ORA  (over-representation analysis) via gseapy.enrichr()
  GSEA (gene set enrichment analysis) via gseapy.prerank()
"""

import argparse
import os
import sys
import warnings

import pandas as pd


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(
        description="Functional enrichment analysis using gseapy (ORA or GSEA)."
    )
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument(
        "--de-results", metavar="FILE",
        help="DE results TSV (required columns: gene_id, log2FoldChange, padj)"
    )
    input_group.add_argument(
        "--ranked-list", metavar="FILE",
        help="Pre-ranked gene list TSV (required columns: gene_id, score)"
    )
    parser.add_argument(
        "--analysis", choices=["ora", "gsea"], default=None,
        help="Analysis type: ora or gsea (default: ora for --de-results, gsea for --ranked-list)"
    )
    parser.add_argument(
        "--organism", default="hsa", choices=["hsa", "mmu", "rno", "dre"],
        help="Organism code: hsa, mmu, rno, dre (default: hsa)"
    )
    parser.add_argument(
        "--gene-id-type", default="SYMBOL", choices=["SYMBOL", "ENSEMBL", "ENTREZID"],
        help="Gene ID type in input file (default: SYMBOL)"
    )
    parser.add_argument(
        "--databases", default="go,kegg",
        help="Comma-separated databases: go,kegg,reactome (default: go,kegg)"
    )
    parser.add_argument(
        "--fdr", type=float, default=0.05,
        help="FDR cutoff for ORA gene filtering and result display (default: 0.05)"
    )
    parser.add_argument(
        "--min-gs-size", type=int, default=5,
        help="Minimum gene set size (default: 5)"
    )
    parser.add_argument(
        "--max-gs-size", type=int, default=500,
        help="Maximum gene set size (default: 500)"
    )
    parser.add_argument(
        "--outdir", default="enrichment_results",
        help="Output directory (default: enrichment_results)"
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Library name maps for gseapy.enrichr()
# ---------------------------------------------------------------------------
ENRICHR_LIBRARY_MAP = {
    # (organism, database) -> list of Enrichr library names
    ("hsa", "go"):       [
        "GO_Biological_Process_2023",
        "GO_Cellular_Component_2023",
        "GO_Molecular_Function_2023",
    ],
    ("hsa", "kegg"):     ["KEGG_2021_Human"],
    ("hsa", "reactome"): ["Reactome_2022"],
    ("mmu", "go"):       [
        "GO_Biological_Process_2023",
        "GO_Cellular_Component_2023",
        "GO_Molecular_Function_2023",
    ],
    ("mmu", "kegg"):     ["KEGG_2019_Mouse"],
    ("mmu", "reactome"): ["Reactome_2022"],
    # For rno and dre, fall back to human libraries as gseapy Enrichr has limited coverage
    ("rno", "go"):       ["GO_Biological_Process_2023", "GO_Molecular_Function_2023"],
    ("rno", "kegg"):     ["KEGG_2021_Human"],
    ("dre", "go"):       ["GO_Biological_Process_2023", "GO_Molecular_Function_2023"],
    ("dre", "kegg"):     ["KEGG_2021_Human"],
}

PRERANK_LIBRARY_MAP = {
    # (organism, database) -> Enrichr gene set library for prerank
    ("hsa", "go"):       "GO_Biological_Process_2023",
    ("hsa", "kegg"):     "KEGG_2021_Human",
    ("hsa", "reactome"): "Reactome_2022",
    ("mmu", "go"):       "GO_Biological_Process_2023",
    ("mmu", "kegg"):     "KEGG_2019_Mouse",
    ("mmu", "reactome"): "Reactome_2022",
    ("rno", "go"):       "GO_Biological_Process_2023",
    ("rno", "kegg"):     "KEGG_2021_Human",
    ("dre", "go"):       "GO_Biological_Process_2023",
    ("dre", "kegg"):     "KEGG_2021_Human",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def strip_ensembl_version(series: pd.Series) -> pd.Series:
    """Remove version suffixes from Ensembl IDs (ENSG00000123.5 → ENSG00000123)."""
    return series.str.replace(r"\.\d+$", "", regex=True)


def save_table(df: pd.DataFrame, path: str, label: str) -> None:
    if df is None or df.empty:
        print(f"  No significant results for {label}; skipping table.")
        return
    df.to_csv(path, sep="\t", index=False)
    print(f"  {label} table written to: {path} ({len(df)} terms)")


def try_import_gseapy():
    try:
        import gseapy
        return gseapy
    except ImportError:
        print("ERROR: gseapy is not installed. Install with: pip install gseapy", file=sys.stderr)
        sys.exit(1)


def try_import_matplotlib():
    try:
        import matplotlib
        matplotlib.use("Agg")  # non-interactive backend
        import matplotlib.pyplot as plt
        return plt
    except ImportError:
        warnings.warn("matplotlib not available; skipping plots.")
        return None


def print_top_results(df: pd.DataFrame, label: str, n: int = 10) -> None:
    if df is None or df.empty:
        print(f"  {label}: no significant results.")
        return
    # Prefer Adjusted P-value column; fall back to P-value
    padj_col = next((c for c in df.columns if "adjusted" in c.lower() or "fdr" in c.lower()), None)
    if padj_col is None:
        padj_col = next((c for c in df.columns if "p-value" in c.lower() or "pvalue" in c.lower()), None)
    term_col = next((c for c in df.columns if "term" in c.lower() or "pathway" in c.lower()), df.columns[0])
    top = df.head(n)
    print(f"\n  Top {len(top)} {label} results:")
    for _, row in top.iterrows():
        padj = row[padj_col] if padj_col else "N/A"
        term = row[term_col]
        print(f"    {term}  (FDR={padj:.3g})" if isinstance(padj, float) else f"    {term}")


def save_dotplot(df: pd.DataFrame, path: str, title: str, plt, top_n: int = 20) -> None:
    if plt is None or df is None or df.empty:
        return
    try:
        # Identify key columns
        term_col  = next((c for c in df.columns if "term" in c.lower() or "pathway" in c.lower()), df.columns[0])
        padj_col  = next((c for c in df.columns if "adjusted" in c.lower() or "fdr" in c.lower()), None)
        if padj_col is None:
            padj_col = next((c for c in df.columns if "p-value" in c.lower()), None)

        plot_df = df.head(top_n).copy()
        if padj_col:
            plot_df = plot_df.sort_values(padj_col)
            import numpy as np
            plot_df["-log10(FDR)"] = -np.log10(plot_df[padj_col].clip(lower=1e-300))
            x_col = "-log10(FDR)"
        else:
            x_col = df.columns[2]  # fallback

        fig, ax = plt.subplots(figsize=(8, max(4, len(plot_df) * 0.35)))
        ax.barh(plot_df[term_col].str[:60], plot_df[x_col], color="steelblue", edgecolor="white")
        ax.set_xlabel(x_col)
        ax.set_title(title)
        ax.invert_yaxis()
        plt.tight_layout()
        fig.savefig(path, dpi=150)
        plt.close(fig)
        print(f"  Dotplot written to: {path}")
    except Exception as exc:
        warnings.warn(f"Dotplot failed for {title}: {exc}")


# ---------------------------------------------------------------------------
# ORA workflow
# ---------------------------------------------------------------------------
def run_ora(args, gseapy, plt, databases, outdir):
    print("=== Over-Representation Analysis (ORA) via gseapy.enrichr() ===\n")

    de = pd.read_csv(args.de_results, sep="\t")
    required = {"gene_id", "padj"}
    missing = required - set(de.columns)
    if missing:
        print(f"ERROR: DE results table missing columns: {missing}", file=sys.stderr)
        sys.exit(1)

    print(f"Total genes in DE table: {len(de)}")

    if args.gene_id_type == "ENSEMBL":
        de["gene_id"] = strip_ensembl_version(de["gene_id"])

    sig_de = de[de["padj"].notna() & (de["padj"] < args.fdr)]
    print(f"Significant genes (padj < {args.fdr}): {len(sig_de)}")

    if sig_de.empty:
        print(f"ERROR: No genes pass FDR {args.fdr}. Consider relaxing --fdr.", file=sys.stderr)
        sys.exit(1)

    gene_list = sig_de["gene_id"].dropna().unique().tolist()

    for db in databases:
        libraries = ENRICHR_LIBRARY_MAP.get((args.organism, db), [])
        if not libraries:
            print(f"  No Enrichr libraries configured for organism={args.organism}, db={db}; skipping.")
            continue

        for lib in libraries:
            label = f"ORA {db.upper()} ({lib})"
            print(f"\n--- {label} ---")
            try:
                enr = gseapy.enrichr(
                    gene_list=gene_list,
                    gene_sets=lib,
                    outdir=None,            # suppress file output; we handle it
                    no_plot=True,
                    cutoff=args.fdr,
                )
                result_df = enr.results
                # Filter by adjusted p-value and gene set size
                padj_col = next((c for c in result_df.columns if "adjusted" in c.lower()), None)
                if padj_col:
                    result_df = result_df[result_df[padj_col] < args.fdr]
                # Filter gene set size
                if "Overlap" in result_df.columns:
                    # Overlap column is formatted as "k/n"
                    bg_size = result_df["Overlap"].str.split("/").str[1].astype(float, errors="ignore")
                    result_df = result_df[
                        bg_size.between(args.min_gs_size, args.max_gs_size)
                    ]

                safe_lib = lib.replace(" ", "_").replace("/", "_")
                out_path = os.path.join(outdir, f"{db}_{safe_lib}_enrichment.tsv")
                save_table(result_df, out_path, label)
                print_top_results(result_df, label)

                # Dotplot
                if plt is not None:
                    plot_path = os.path.join(outdir, f"{db}_{safe_lib}_dotplot.pdf")
                    save_dotplot(result_df, plot_path, f"{label} - Top 20", plt)

            except Exception as exc:
                warnings.warn(f"{label} failed: {exc}")


# ---------------------------------------------------------------------------
# GSEA workflow
# ---------------------------------------------------------------------------
def run_gsea(args, gseapy, plt, databases, outdir):
    print("=== Gene Set Enrichment Analysis (GSEA) via gseapy.prerank() ===\n")

    if args.ranked_list:
        rl = pd.read_csv(args.ranked_list, sep="\t")
        if not {"gene_id", "score"}.issubset(rl.columns):
            print("ERROR: Ranked list must have columns: gene_id, score", file=sys.stderr)
            sys.exit(1)
        if args.gene_id_type == "ENSEMBL":
            rl["gene_id"] = strip_ensembl_version(rl["gene_id"])
        rank_df = rl[["gene_id", "score"]].dropna()
    else:
        de = pd.read_csv(args.de_results, sep="\t")
        required = {"gene_id", "log2FoldChange", "padj"}
        missing = required - set(de.columns)
        if missing:
            print(f"ERROR: DE results missing columns for GSEA: {missing}", file=sys.stderr)
            sys.exit(1)
        if args.gene_id_type == "ENSEMBL":
            de["gene_id"] = strip_ensembl_version(de["gene_id"])
        import numpy as np
        padj_floor = de["padj"].clip(lower=1e-300)
        de["score"] = -np.log10(padj_floor) * de["log2FoldChange"].apply(
            lambda x: 1 if x >= 0 else -1
        )
        rank_df = de[["gene_id", "score"]].dropna()
        print(f"Genes with valid ranking scores: {len(rank_df)}")

    # Deduplicate: keep highest absolute score per gene
    rank_df = rank_df.reindex(rank_df["score"].abs().sort_values(ascending=False).index)
    rank_df = rank_df.drop_duplicates(subset="gene_id")
    rank_df = rank_df.sort_values("score", ascending=False)
    print(f"Genes in ranked list after deduplication: {len(rank_df)}")

    # Convert to gseapy format: dict {gene: score}
    rnk = rank_df.set_index("gene_id")["score"]

    for db in databases:
        lib = PRERANK_LIBRARY_MAP.get((args.organism, db))
        if lib is None:
            print(f"  No prerank library configured for organism={args.organism}, db={db}; skipping.")
            continue

        label = f"GSEA {db.upper()} ({lib})"
        print(f"\n--- {label} ---")
        try:
            pre_res = gseapy.prerank(
                rnk=rnk,
                gene_sets=lib,
                min_size=args.min_gs_size,
                max_size=args.max_gs_size,
                permutation_num=1000,
                outdir=None,
                no_plot=True,
                seed=42,
                verbose=False,
            )
            result_df = pre_res.res2d

            # Filter by FDR
            fdr_col = next((c for c in result_df.columns if "fdr" in c.lower()), None)
            if fdr_col:
                result_df = result_df[result_df[fdr_col].astype(float) < args.fdr]

            safe_lib = lib.replace(" ", "_").replace("/", "_")
            out_path = os.path.join(outdir, f"gsea_{db}_{safe_lib}_results.tsv")
            save_table(result_df, out_path, label)
            print_top_results(result_df, label)

            # Dotplot
            if plt is not None:
                plot_path = os.path.join(outdir, f"gsea_{db}_{safe_lib}_dotplot.pdf")
                save_dotplot(result_df, plot_path, f"{label} - Top 20", plt)

        except Exception as exc:
            warnings.warn(f"{label} failed: {exc}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    args = parse_args()

    # Infer analysis type
    if args.analysis is None:
        args.analysis = "ora" if args.de_results else "gsea"

    # Normalize arg names for mutual exclusivity (argparse uses underscores)
    # args.de_results and args.ranked_list are already set by argparse

    os.makedirs(args.outdir, exist_ok=True)

    print("=== RNA-seq Functional Enrichment (gseapy) ===")
    print(f"Analysis:      {args.analysis}")
    print(f"Organism:      {args.organism}")
    print(f"Gene ID type:  {args.gene_id_type}")
    print(f"Databases:     {args.databases}")
    print(f"FDR cutoff:    {args.fdr}")
    print(f"Gene set size: {args.min_gs_size} – {args.max_gs_size}")
    print(f"Output dir:    {args.outdir}")
    if args.de_results:
        print(f"Input:         {args.de_results} (DE results)")
    else:
        print(f"Input:         {args.ranked_list} (ranked gene list)")
    print()

    gseapy = try_import_gseapy()
    plt    = try_import_matplotlib()

    databases = [d.strip().lower() for d in args.databases.split(",") if d.strip()]

    if args.analysis == "ora":
        if not args.de_results:
            print("ERROR: --de-results is required for ORA analysis.", file=sys.stderr)
            sys.exit(1)
        run_ora(args, gseapy, plt, databases, args.outdir)

    elif args.analysis == "gsea":
        run_gsea(args, gseapy, plt, databases, args.outdir)

    else:
        print(f"ERROR: Unknown analysis type '{args.analysis}'.", file=sys.stderr)
        sys.exit(1)

    print("\n=== Functional enrichment analysis complete ===")
    print(f"Output directory: {args.outdir}")


if __name__ == "__main__":
    main()
