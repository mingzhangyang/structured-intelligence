# NGS Analysis Expert: Orchestrating End-to-End Genomic Data Workflows with Skill-Based AI

## Abstract

Next-generation sequencing (NGS) analysis demands sustained expertise across a layered set of tasks: locating public datasets in heterogeneous archives, downloading them with correct access handling and integrity verification, and then running complex multi-step computational pipelines that differ substantially by sequencing modality. Each layer carries its own vocabulary, toolchain, and failure modes, and in practice researchers must coordinate all of them to answer a single biological question. This manuscript introduces `ngs-analysis-expert`, an AI orchestration agent backed by a collection of 34 purpose-built skills that spans the complete data lifecycle — from structured queries against NCBI SRA, GEO, ENA, GSA, and the NCBI Datasets portal through raw-data acquisition via SRA Toolkit and GDC client to full analysis pipelines covering whole-genome and whole-exome variant calling, bulk RNA-seq differential expression, single-cell RNA-seq, and shotgun metagenomics. The agent does not replace any of the underlying tools; it provides a policy layer that selects the correct pipeline for a stated scientific question, delegates each step to the appropriate skill, enforces quality checkpoints between steps, and explains tool-choice tradeoffs in terms relevant to the user's experimental design. Together, the agent and its skill library demonstrate that genomic analysis workflows can be decomposed into auditable, reusable, and composable components that are accessible through natural-language task descriptions without sacrificing transparency or reproducibility.

## 1. Introduction

The genomics era has produced an extraordinary abundance of public sequencing data and an equally large catalog of established computational tools for analyzing it. Accessing and exploiting this abundance is, in principle, a solved problem: NCBI SRA, GEO, ENA, and related archives make terabytes of raw reads freely available; the GATK best-practices framework, STAR, DESeq2, Cell Ranger, Kraken2, and dozens of peer-reviewed tools provide vetted analysis pipelines. Yet in practice, the path from a scientific question to a finished analysis result remains laborious, error-prone, and highly dependent on individual expertise [1-3].

The obstacles are procedural, not conceptual. A researcher who wants to compare microbial community composition between two patient cohorts understands the biology perfectly well. What stands between them and a usable answer is a chain of specific operational decisions: which archive holds the relevant data, what query syntax that archive requires, how to expand a BioProject accession to individual run accessions, how to invoke prefetch and fasterq-dump correctly, how to handle paired-end read splitting, when host removal is mandatory, which of Kraken2 and MetaPhlAn 4 is appropriate for their sequencing depth, and what QC thresholds indicate that a sample should be excluded before taxonomic profiling begins. Each decision is individually learnable, but together they form a steep, persistent learning curve.

The AI era offers a new approach to this problem. Rather than expecting every researcher to traverse this learning curve independently, a correctly specified AI agent can encode established practices as executable policies, delegate individual operations to deterministic skill bundles, and mediate between a user's natural-language description of a goal and the precise sequence of commands that achieves it. This manuscript describes a concrete implementation of that approach: the `ngs-analysis-expert` agent, its supporting skill library, and the design decisions that connect them.

## 2. The Data Lifecycle in Genomic Research

A realistic genomic analysis workflow involves three distinct phases that are often treated as separate concerns but are tightly coupled in practice.

### 2.1 Dataset discovery

Before any analysis can begin, a researcher must locate the relevant raw data. The public archives that hold sequencing data are numerous and partially overlapping: NCBI SRA stores the largest collection of raw sequencing runs, NCBI GEO provides processed expression data alongside SRA links for RNA-seq studies, the European Nucleotide Archive (ENA) mirrors most SRA submissions and exposes a REST API distinct from NCBI E-utilities, the CNCB Genome Sequence Archive (GSA) holds a growing collection of data deposited by investigators in Asia, and the NCBI Datasets portal provides genome assemblies, gene records, and virus genomes. Each archive uses its own accession vocabulary, query syntax, and metadata schema. Researchers who work across archives must maintain knowledge of all of them.

### 2.2 Data acquisition

Having identified the relevant accessions, a researcher must download the data. SRA data requires the SRA Toolkit (`prefetch`, `fasterq-dump`), with special handling for dbGaP-controlled accessions, paired-end read splitting, and temporary disk space requirements. GEO supplementary files and series matrices are accessible by FTP, but with accession-specific directory path conventions. NCI GDC data requires the GDC Data Transfer Tool with per-token authentication for controlled-access TCGA and TARGET cohorts. Each download pathway has distinct failure modes: SRA can time out on large runs; GDC tokens expire after 30 days; GEO FTP paths use a numeric prefix convention that is easy to compute incorrectly.

### 2.3 Pipeline execution

Once raw data is available locally, the analysis begins. The correct pipeline structure depends on the sequencing modality, the experimental design, and the scientific question. Whole-genome and whole-exome sequencing (WGS/WES) variant calling follows GATK best practices but requires different filtering strategies at different sample counts. RNA-seq differential expression can use alignment-based counting or alignment-free transcript quantification, and the choice affects downstream compatibility with DESeq2 and edgeR. Single-cell RNA-seq introduces an additional layer of complexity around ambient RNA removal, doublet detection, clustering, cell-type annotation, batch correction, and pseudobulk versus single-cell differential expression. Shotgun metagenomics must address host decontamination, and the optimal profiling tool (Kraken2/Bracken versus MetaPhlAn 4) depends on the desired tradeoff between database coverage and species-level precision.

No single pipeline covers all three phases coherently for all modalities. Researchers typically assemble this knowledge from multiple documentation sources, ad hoc scripts, and institutional memory. The agent described here is an attempt to encode that assembly explicitly.

## 3. Architecture: Agent Plus Skill Library

The implementation centers on two elements: an orchestrating agent and a library of composable skills.

### 3.1 The orchestrating agent

`ngs-analysis-expert` is defined as an agent with an explicit system prompt, a pipeline-selection table, and a complete inventory of the skills it can invoke. Its policy encodes the decisions that an experienced bioinformatician would make before and during a sequencing analysis:

- Always assess QC before downstream steps.
- Match the pipeline structure to the stated experimental question using a canonical workflow document for each modality.
- Validate outputs at each checkpoint before proceeding.
- Prefer established defaults (GATK, STAR two-pass, fastp, DESeq2) and explain deviations.
- Delegate each operation to the appropriate registered skill rather than issuing raw commands.
- Ask clarifying questions when the experimental design is ambiguous, rather than guessing.

The agent's pipeline-selection logic maps natural-language descriptions to canonical workflows. A user who says "call germline variants from WGS" is routed to the WGS/WES variant-calling workflow; "find differentially expressed genes between treated and control" routes to RNA-seq differential expression; "profile gut microbiome composition" routes to shotgun metagenomics. Within each workflow, the agent consults canonical step-order documents and shared knowledge files covering file formats, reference genome builds, platform-specific quality thresholds, and R/Bioconductor environment setup.

The agent also handles multi-sample design explicitly. For cohort-scale WGS analysis, it orchestrates per-sample processing followed by GVCF-mode joint genotyping. For RNA-seq, it assembles a count matrix across samples before differential expression. For metagenomics, it coordinates per-sample taxonomic profiling followed by multi-sample table merging. These aggregation steps are precisely where individual-sample scripts most often fail at scale, and encoding them in the agent policy makes them consistent across analyses.

### 3.2 Skill library overview

The skill library contains 34 skills organized in five functional groups.

**Public database search (5 skills)**: `search-sra`, `search-geo`, `search-ena`, `search-gsa`, and `search-ncbi-datasets`. These skills encapsulate the query syntax, field-tag conventions, metadata parsing, and output formatting for each archive. A user can request "find all paired-end RNA-seq datasets for Homo sapiens deposited in SRA since 2022" and receive a formatted run table with accession, platform, library layout, read count, and file size, along with a ready-made accession list for batch download.

**Data download (3 skills)**: `download-sra`, `download-geo`, and `download-gdc`. Each skill encapsulates the correct download tool, authentication handling, integrity verification, and output layout for its target archive. `download-sra` manages the prefetch-then-fasterq-dump two-step for individual or batch SRR accessions, expands BioProject and study accessions to their full run lists, and writes a manifest with MD5 checksums. `download-geo` resolves the archive-specific FTP path convention, downloads supplementary files and series matrices, and can extract the SRA accession list associated with a GEO series for handoff to `download-sra`. `download-gdc` handles both open-access and controlled-access GDC files, validates the manifest, and reports MD5 verification results per file.

**Environment setup (1 skill)**: `bioinformatics-env-setup` provides conda environment definitions for each pipeline modality (WGS, RNA-seq, metagenomics, single-cell) and installation guidance for tools that fall outside conda channels. The NGS analysis expert proactively invokes this skill when a required tool is not found or when a user begins a new pipeline without confirming their environment.

**NGS analysis skills (26 skills)**: The analysis skills are organized by modality, following the canonical workflow structure for each.

## 4. Skill Groups in Detail

### 4.1 Public database search skills

The five search skills cover the major repositories for raw sequencing data and reference genomes. Each skill handles a distinct access model and query convention.

`search-sra` uses NCBI E-utilities (`esearch`, `efetch -format runinfo`) to query the SRA database by free text, structured field tags, or bare accession. It supports accession-type routing: bare SRR accessions are used directly; PRJNA or SAMN accessions are linked through the bioproject and biosample databases to their associated SRA runs. Output includes a tabular run summary and a plain-text accession list ready for `download-sra`.

`search-geo` queries the NCBI GEO and GDS databases for expression series, samples, and platforms. It handles the important distinction between the `geo` database (sample-level) and `gds` (series-level curated datasets), which affects query design. For series-level accessions, it can enumerate all associated GSM samples and return supplementary file links.

`search-ena` uses the ENA Portal REST API, which provides FASTQ download URLs directly in the metadata response — a significant operational advantage over the NCBI approach. It handles ENA's Lucene query syntax and taxonomy filtering (including `tax_tree()` for taxonomic descendants), and it extracts `fastq_ftp` URLs for direct download without requiring additional tool installation.

`search-gsa` targets the CNCB Genome Sequence Archive, which hosts data from investigators who deposit primarily through CNSA/CNCB. It handles GSA's distinct accession namespace (CRA for projects, CRX for experiments, CRR for runs, CRS for samples) and constructs the correct CNCB API and FTP paths for metadata retrieval and download.

`search-ncbi-datasets` wraps both the NCBI Datasets CLI and its REST API for genome assembly, gene, and virus queries. It handles assembly-level filtering, annotation status, RefSeq versus GenBank source selection, dehydrated download packages, and the `dataformat` reformatter for TSV output from JSON summaries.

### 4.2 Data download skills

`download-sra` implements the recommended SRA Toolkit workflow: resolve the accession to SRR identifiers (expanding study, experiment, and sample accessions as needed), run `prefetch` to cache the `.sra` file, run `vdb-validate` for integrity verification, run `fasterq-dump --split-3` to produce paired-end FASTQ files, and gzip compress. For batch downloads, it supports GNU parallel or sequential processing with per-run logging. It writes a manifest TSV with output file paths and MD5 checksums for downstream pipeline handoff.

`download-geo` resolves the GEO FTP directory path from the GSE accession (applying the correct numeric-prefix convention), downloads supplementary files, series matrices, and optionally the full SOFT metadata file. In `sra-list` mode, it extracts the SRR accessions linked to the series and generates the recommended `download-sra` command — connecting the GEO and SRA download skills into a coherent two-step workflow for raw RNA-seq data.

`download-gdc` handles both manifest-based and query-based GDC downloads. For query-based use, it constructs a GDC API POST request with project, data type, experimental strategy, and access-tier filters to build a manifest on the fly. It invokes `gdc-client` with the appropriate token, validates each downloaded file against the MD5 checksum from the manifest, and produces a download report with per-file status.

### 4.3 NGS shared skills

`ngs-quality-control` wraps FastQC and MultiQC for raw read quality assessment across all modalities. It checks per-base quality, adapter content, GC distribution, and sequence duplication levels, and it flags samples against platform-specific thresholds from the shared knowledge base.

`ngs-read-preprocessing` wraps fastp for adapter trimming and quality filtering. It applies polyG trimming for NovaSeq and NextSeq data, reports trimming statistics, and verifies that survival rates and post-trimming quality meet the thresholds required before alignment.

### 4.4 WGS/WES variant-calling skills

The five WGS/WES skills implement the GATK best-practices pipeline in skill form.

`genome-read-alignment` aligns trimmed reads to the reference genome with BWA-MEM2, sorts and indexes the output with samtools, and marks duplicates with Picard MarkDuplicates. It enforces read-group tagging, which is a prerequisite for downstream GATK compatibility. For WES, it applies the capture BED file at the alignment stage.

`genome-alignment-qc` assesses alignment quality using samtools stats, mosdepth (for depth and uniformity), and Picard CollectMultipleMetrics. For WES, it calculates on-target rate against the capture BED. It applies pass/fail thresholds: ≥95% mapping rate, <15% duplication for WGS, ≥30× mean coverage for germline WGS, ≥50× on-target for WES.

`genome-variant-calling` supports GATK HaplotypeCaller in GVCF mode (for cohorts requiring joint genotyping) or direct VCF mode, as well as DeepVariant for higher-sensitivity applications. For WES, it restricts calling to the capture intervals.

`genome-variant-filtering` applies GATK VQSR for cohorts meeting the training variant count threshold (≥30 exomes or ≥1 WGS), and hard filters for smaller sample sets. It annotates PASS and filter labels and reports Ti/Tv ratios as a post-filter quality metric.

`genome-variant-annotation` applies SnpEff or VEP to annotate filtered variants with gene consequence, population allele frequency from gnomAD, and clinical significance from ClinVar. HIGH-impact variants and those flagged in ClinVar are surfaced explicitly in the annotation summary.

### 4.5 RNA-seq skills

The six RNA-seq skills support both an alignment-based counting path and an alignment-free quantification path to the same differential expression endpoint.

`rnaseq-read-alignment` aligns with STAR in two-pass mode (the recommended default for novel junction discovery) or HISAT2 when memory is constrained. It ingests the GTF annotation file to build the splice-junction database and produces a sorted, indexed BAM.

`rnaseq-alignment-qc` runs RSeQC and Qualimap to assess strandedness, gene body coverage uniformity, rRNA contamination rate, and read-distribution across feature types. Strandedness detection at this step is critical: an incorrect strandedness setting propagates into counting and produces systematically wrong gene-level quantifications.

`rnaseq-read-counting` runs featureCounts or HTSeq-count to generate a gene-level count matrix. It applies the strandedness setting confirmed at the QC step and produces a summary of assigned, ambiguous, and unassigned reads.

`rnaseq-transcript-quantification` provides the alignment-free alternative: Salmon or kallisto quantification against a transcript index. The output quant files are consumed by tximport in the downstream differential expression step to produce gene-level summarized estimates that propagate transcript-level uncertainty into the count model.

`rnaseq-differential-expression` runs DESeq2 (default) or edgeR. It accepts either a featureCounts count matrix directly or a set of Salmon/kallisto quant directories via tximport. Design formula construction, batch covariate handling, and default thresholds (FDR < 0.05, |log2FC| > 1) are explicitly documented. It produces DE results tables, PCA plots, volcano plots, MA plots, and clustered expression heatmaps.

`rnaseq-functional-enrichment` applies gene ontology and pathway enrichment analysis to DE results using clusterProfiler and MSigDB gene sets. It performs over-representation analysis (ORA) for gene lists and gene set enrichment analysis (GSEA) for ranked results, producing enrichment tables and dot plots.

### 4.6 Single-cell RNA-seq skills

The seven scRNA-seq skills cover the full analytical lifecycle from raw FASTQ to trajectory inference.

`scrnaseq-cellranger-count` runs Cell Ranger count or STARsolo to generate feature-barcode count matrices from 10x Chromium or similar droplet-based libraries. It handles chemistry version selection, intron inclusion for multiome or snRNA-seq data, and the summary report.

`scrnaseq-quality-control` addresses the two major sources of technical artifact in droplet sequencing: ambient RNA contamination and doublets. It applies SoupX or CellBender for ambient correction and Scrublet or scDblFinder for doublet scoring, then applies per-cell filtering on gene count, UMI count, and mitochondrial read fraction. Thresholds are tissue-type-aware: brain neurons tolerate higher mitochondrial percentages than immune cells, and aggressive gene-count thresholds can eliminate genuine rare populations.

`scrnaseq-clustering` normalizes count data, identifies highly variable genes, performs PCA-based dimensionality reduction, builds a nearest-neighbor graph, applies Leiden or Louvain community detection at a tunable resolution, and produces UMAP embeddings. It supports Scanpy and Seurat workflows interchangeably.

`scrnaseq-cell-type-annotation` assigns biological identities to clusters using marker-gene scoring (sc-type, SingleR), manual marker inspection, and optionally large-scale reference-based label transfer. It produces a labeled UMAP and a per-cluster marker table.

`scrnaseq-differential-expression` supports two modes: single-cell Wilcoxon tests for exploratory cluster comparisons, and pseudobulk DESeq2 for multi-sample designs with biological replicates. The agent's system prompt explicitly directs users toward pseudobulk analysis when multiple donors are present, because single-cell Wilcoxon tests underestimate variance across biological samples and produce inflated false-discovery rates.

`scrnaseq-integration` corrects batch effects across samples or datasets using Harmony (PCA-embedding correction), scVI (deep generative model), or Seurat RPCA. It handles the important constraint that Harmony-corrected embeddings should not be used for differential expression: integration is for visualization and clustering, not for count-level modeling.

`scrnaseq-trajectory-analysis` fits developmental trajectories using Monocle 3 or scVelo. Monocle 3 learns a principal-graph trajectory from UMAP coordinates; scVelo uses spliced and unspliced RNA velocities estimated from the count matrix to infer directionality without requiring a user-specified root state.

### 4.7 Metagenomics skills

The five metagenomics skills address the specific challenges of community-level sequencing data, where reads originate from multiple organisms simultaneously and host contamination is a first-order concern for clinical and human-associated samples.

`metagenome-host-removal` aligns reads to the host reference genome (GRCh38 for human samples) with Bowtie2 or BWA-MEM2 and extracts the unmapped pairs. It applies a ≥95% host-removal target, and for non-host-associated environments (soil, ocean, industrial) it supports minimal or absent host references.

`metagenome-taxonomic-profiling` supports Kraken2/Bracken (k-mer-based, fast, broad database coverage) and MetaPhlAn 4 (marker-gene-based, higher species-level precision, smaller database). The agent explicitly documents the tradeoff: Kraken2 provides higher sensitivity across diverse communities; MetaPhlAn 4 is preferred when precision at the species level is more important than breadth.

`metagenome-assembly` assembles host-depleted reads into contigs with MEGAHIT (the default for its low memory footprint, typically 10–50 GB) or metaSPAdes (higher contiguity but 100–500 GB RAM). It filters the resulting contigs to a minimum length of 1000 bp.

`metagenome-binning` recovers metagenome-assembled genomes (MAGs) from assembled contigs using coverage depth and tetranucleotide frequency signals. It applies MetaBAT2 as the primary binner, optionally combines multiple binners with DAS Tool for improved bin recovery, and assesses bin quality with CheckM2 against MIMAG quality standards (high-quality: ≥90% complete, <5% contamination).

`metagenome-functional-profiling` annotates metabolic potential using three complementary approaches: HUMAnN 3 for read-based gene family and pathway abundance profiling (producing MetaCyc pathway tables), Prokka for gene prediction from contigs or MAGs, and eggNOG-mapper for COG, KEGG, and GO ortholog assignment to predicted proteins.

## 5. Design Principles

### 5.1 Skills encode operational knowledge, not just commands

Each skill is more than a wrapper around a tool invocation. It encodes the pre-conditions for correct use, the decision criteria for parameter selection, the expected output structure, and the common failure modes. The `rnaseq-alignment-qc` skill, for example, does not simply run RSeQC; it explains that strandedness must be confirmed at this step and explicitly connected to the subsequent counting step, because a strandedness mismatch between counting and the actual library protocol is one of the most common sources of silent errors in RNA-seq pipelines. Similarly, `genome-variant-filtering` explicitly documents the threshold conditions under which VQSR is appropriate versus hard filters, because applying VQSR below the training variant count threshold produces worse results than simple hard filters.

This kind of embedded operational knowledge is precisely what is missing from most bioinformatics documentation, which tends to describe what tools do rather than when to use them, how to choose between alternatives, and what to check when something goes wrong.

### 5.2 Quality checkpoints are non-negotiable

The agent's operating rules enforce quality assessment at every major transition: raw QC before alignment, alignment QC before variant calling or counting, and variant-level Ti/Tv and het/hom ratio assessment after variant calling. These checkpoints exist because pipeline failures in genomics are often silent. A BAM with low mapping rate will proceed through variant calling to produce a VCF; the VCF will look syntactically correct but will be statistically underpowered or systematically biased. The agent does not proceed past a failed checkpoint without explicit user acknowledgment, and it explains the specific metric that triggered the flag and the implications for downstream analysis.

### 5.3 Tool-choice explanations accompany every recommendation

When two tools address the same analysis step, the agent presents the tradeoffs relevant to the user's context rather than issuing an unexplained preference. STAR versus HISAT2: STAR is heavier and requires more memory but provides better novel junction detection; HISAT2 is a reasonable alternative when memory is constrained. GATK HaplotypeCaller versus DeepVariant: DeepVariant is more accurate, especially for indels, but is significantly slower and requires GPU for practical runtime on large genomes. Kraken2 versus MetaPhlAn 4: Kraken2 provides broader coverage against a comprehensive database; MetaPhlAn 4 is more precise at the species level for human-associated communities. Presenting these tradeoffs makes the agent's decisions auditable and gives users the information they need to override a recommendation intelligently.

### 5.4 The search-to-download-to-analysis chain is explicit

A distinctive feature of this skill collection is that it covers the complete data lifecycle from archive discovery through download through analysis as a connected chain. The `search-geo` skill can return an SRR accession list for a GEO series. The `download-geo` skill's `sra-list` mode extracts that list and recommends the exact `download-sra` invocation. The `download-sra` skill writes a manifest that provides the file paths and metadata needed to initialize the `ngs-quality-control` skill. The agent can orchestrate this chain end-to-end when a user presents a scientific question without pre-downloaded data: "Find the RNA-seq datasets from this BioProject, download them, and run a differential expression analysis."

Making this chain explicit and documented is valuable because the handoff points between discovery, acquisition, and analysis are where informal workflows most frequently break down. Archive queries return too many results without filtering; download scripts fail silently on missing accessions; analysis pipelines are started from data whose provenance is not fully recorded. Skills that document their inputs, outputs, and hand-off contracts reduce these failure modes.

### 5.5 Multi-provider compatibility

Each skill in the library is defined for both Claude-family and OpenAI-family providers through parallel agent configuration files. This choice reflects the recognition that research computing environments are heterogeneous: different groups or institutions may have different AI provider contracts or preferences, and a skill library that is vendor-locked provides less durable value than one that works across the major model families.

## 6. Implementation Characteristics

### 6.1 Agent definition

The agent is specified through three files: an `AGENT.md` document that defines purpose, inputs, outputs, operating rules, failure modes, and the pipeline-selection table; a system prompt that provides the agent's identity, behavioral principles, and knowledge references; and a task-prompt template that structures how analysis requests are formatted. This three-layer structure follows the agent template used elsewhere in the Structured Intelligence repository and makes the agent's decision logic inspectable as plain text.

### 6.2 Skill structure

Each of the 34 skills is defined through a `SKILL.md` document, a `config.yaml` for tool registration, provider-specific agent YAML files for Claude and OpenAI, an optional `references/` directory for embedded operational knowledge, and an optional `scripts/` directory for deterministic command-line wrappers. The download skills include shell scripts for single-accession and batch-mode operation. This structure is consistent across skills and validates against the repository's shared schema.

### 6.3 Shared knowledge base

The genomics analysis skills share a common knowledge base under `knowledge/sources/genomics/` containing four files: `file-formats.md` (FASTQ, BAM/SAM, VCF, BED, GFF/GTF specifications), `reference-genomes.md` (standard builds, download sources, and indexing commands), `quality-thresholds.md` (platform-specific and modality-specific pass/fail criteria), and `r-environment-setup.md` (R/Bioconductor installation guidance for DESeq2, edgeR, and related packages). Three canonical workflow documents under `workflows/genomics/` define the step order, inter-skill dependencies, and key decision points for each supported modality.

This shared-knowledge architecture is important for consistency. Rather than embedding QC thresholds redundantly in each individual skill, the skills reference a single authoritative source. When threshold guidance is updated — for example, if revised GATK best-practice recommendations change the recommended minimum coverage for germline WGS — a single edit propagates correctly to all skills and to the agent's checkpoint evaluation.

## 7. Scope and Limitations

The current implementation targets short-read Illumina NGS pipelines. For long-read-only workflows (Oxford Nanopore, PacBio), the agent can provide general principles and tool references but does not have dedicated skills for long-read-specific tools such as Dorado, Clair3, or Flye. Somatic variant calling (tumor/normal paired analysis, Mutect2, somatic CNV) is outside the current scope. Clinical-grade variant interpretation is explicitly outside scope: the annotation skills flag ClinVar entries and HIGH-impact variants but do not constitute medical interpretation.

The agent requires that the user have the necessary tools installed or be willing to invoke `bioinformatics-env-setup` first. It cannot install tools autonomously; it can only provide the environment definitions and installation guidance. Similarly, the search and download skills depend on live access to their respective archive APIs; network-inaccessible environments or archive outages will interrupt these skills in ways that require the user to resolve externally.

The search and download skills handle public and open-access data. For controlled-access data — dbGaP-protected SRA accessions and GDC controlled-tier files — the skills provide guidance on the authentication process (obtaining an ngc token, obtaining a GDC user token) but cannot obtain authorization on the user's behalf. Users remain responsible for complying with the data use agreements, terms of service, and access conditions of the original archives.

As with all AI-mediated scientific workflows, the agent's outputs are a function of both the encoded operational knowledge and the underlying model's inference. The skills and agent policy encode correct practice to the best of the authors' knowledge at the time of implementation, but bioinformatics best practices evolve. Users should verify that tool versions, database versions, and recommended parameters remain current for their analysis context, particularly for rapidly evolving areas such as long-read alignment, single-cell analysis, and viral genomics.

## 8. Availability

The `ngs-analysis-expert` agent and all 34 associated skills are implemented within the Structured Intelligence repository, which is publicly available at `https://github.com/Scientific-Tooling/structured-intelligence` (accessed March 15, 2026). The repository is distributed under the MIT License. The relevant materials are located under:

- `agents/ngs-analysis-expert/` — agent definition, system prompt, and task template
- `skills/search-sra/`, `skills/search-geo/`, `skills/search-ena/`, `skills/search-gsa/`, `skills/search-ncbi-datasets/` — archive search skills
- `skills/download-sra/`, `skills/download-geo/`, `skills/download-gdc/` — data download skills
- `skills/bioinformatics-env-setup/` — environment setup skill
- `skills/ngs-quality-control/`, `skills/ngs-read-preprocessing/` — shared NGS skills
- `skills/genome-*/` — WGS/WES variant-calling skills
- `skills/rnaseq-*/` — bulk RNA-seq skills
- `skills/scrnaseq-*/` — single-cell RNA-seq skills
- `skills/metagenome-*/` — metagenomics skills
- `workflows/genomics/` — canonical pipeline workflow documents
- `knowledge/sources/genomics/` — shared quality thresholds, file formats, and reference genome guidance

Skills can be installed into supported AI coding assistants using the bundled `scripts/install_skill.sh` script. Individual skills can be installed and used independently of the full agent. The agent orchestrates the full skill set but is not required for users who want only the search, download, or individual analysis skills.

The implementation should be understood as an independent, unofficial interface layer around the upstream tools and services it references. It does not claim ownership of NCBI SRA, GEO, ENA, GSA, GDC, or any other third-party archive, tool, or database, and it does not imply endorsement by those services. Users are responsible for complying with the licenses, terms of service, data use agreements, and attribution requirements of the underlying resources.

## 9. Conclusion

The central contribution of this work is not any individual skill. It is the demonstration that the complete lifecycle of a genomic analysis — from archive query through data acquisition through multi-step pipeline execution — can be decomposed into composable, auditable skill bundles and orchestrated by a policy-encoding agent. The resulting system is transparent because each skill documents its decision logic, expected outputs, and failure modes. It is reproducible because the agent follows canonical workflow documents with explicit quality checkpoints. It is accessible because users can express analysis goals in natural language without understanding the full toolchain in advance.

Bioinformatics tooling has historically required users to choose between accessibility and depth. High-level platforms such as Galaxy provide accessibility but reduce flexibility; raw command-line workflows provide full control but require sustained expertise to operate correctly. Skill-based AI orchestration offers a different point in this design space: flexible enough to handle diverse experimental designs and scientific questions, but accessible enough for investigators who have not specialized in bioinformatics. Making expert practice encodable and reusable — rather than tacit and individually held — is a meaningful contribution to how genomic science is practiced.

## References

1. GATK Best Practices. Broad Institute. Available from: https://gatk.broadinstitute.org/hc/en-us/sections/360007226651-Best-Practices-Workflows
2. Conesa A, Madrigal P, Tarazona S, Gomez-Cabrero D, Cervera A, McPherson A, et al. A survey of best practices for RNA-seq data analysis. Genome Biol. 2016;17:13. doi:10.1186/s13059-016-0881-8
3. Ewels PA, Peltzer A, Fillinger S, Patel H, Alneberg J, Wilm A, et al. The nf-core framework for community-curated bioinformatics pipelines. Nat Biotechnol. 2020;38(3):276-278. doi:10.1038/s41587-020-0439-x
4. Lander ES, Linton LM, Birren B, Nusbaum C, Zody MC, Baldwin J, et al. Initial sequencing and analysis of the human genome. Nature. 2001;409(6822):860-921. doi:10.1038/35057062
5. Dobin A, Davis CA, Schlesinger F, Drenkow J, Zaleski C, Jha S, et al. STAR: ultrafast universal RNA-seq aligner. Bioinformatics. 2013;29(1):15-21. doi:10.1093/bioinformatics/bts635
6. Li H, Durbin R. Fast and accurate short read alignment with Burrows-Wheeler Aligner. Bioinformatics. 2009;25(14):1765-1767. doi:10.1093/bioinformatics/btp324
7. Love MI, Huber W, Anders S. Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biol. 2014;15(12):550. doi:10.1186/s13059-014-0550-8
8. Hao Y, Stuart T, Kowalski MH, Choudhary S, Hoffman P, Hartman A, et al. Dictionary learning for integrative, multimodal and scalable single-cell analysis. Nat Methods. 2024;21(2):294-302. doi:10.1038/s41592-023-02120-6
9. Blanco-Melo D, Nilsson-Payant BE, Liu WC, Uhl S, Hoagland D, Møller R, et al. Imbalanced host response to SARS-CoV-2 drives development of COVID-19. Cell. 2020;181(5):1036-1045.e9. doi:10.1016/j.cell.2020.04.026
10. Wood DE, Lu J, Langmead B. Improved metagenomic analysis with Kraken 2. Genome Biol. 2019;20(1):257. doi:10.1186/s13059-019-1891-0
11. Sayers EW, Cavanaugh M, Clark K, Pruitt KD, Sherry ST, Yankie L, et al. Database resources of the National Center for Biotechnology Information in 2026. Nucleic Acids Res. 2026. doi:10.1093/nar/gkaf1060
