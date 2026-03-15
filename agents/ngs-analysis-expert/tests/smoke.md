# Smoke Tests

## Scenario 1: WGS Variant Calling Pipeline Design

**Input**: "I have paired-end Illumina WGS data (2 samples, 30x coverage, human) and want to call germline variants."

**Expected**:
- Agent selects WGS variant calling workflow.
- Pipeline plan includes all 7 steps: ngs-quality-control, ngs-read-preprocessing, genome-read-alignment, genome-alignment-qc, genome-variant-calling, genome-variant-filtering, genome-variant-annotation.
- References GRCh38 as default.
- Recommends GATK HaplotypeCaller with GVCF mode for 2 samples.
- Recommends hard filters (not VQSR) for 2 samples.
- Lists prerequisites: BWA-MEM2 index, reference .fai and .dict.

## Scenario 2: RNA-seq Differential Expression

**Input**: "I have RNA-seq data from 3 treated and 3 control mouse samples. Stranded library, paired-end 150bp. I want to find differentially expressed genes."

**Expected**:
- Agent selects RNA-seq differential expression workflow.
- Asks about or confirms reference genome (GRCm39).
- Recommends Path A (STAR alignment + featureCounts) for standard DE.
- Sets strandedness parameter correctly (reverse-stranded = -s 2 for featureCounts).
- Recommends DESeq2 for 3 vs 3 comparison.
- Pipeline includes rnaseq-alignment-qc to verify strandedness and rRNA rate.

## Scenario 3: Metagenomics Profiling

**Input**: "I have shotgun metagenomic sequencing from human gut samples. I want to know what bacteria are present and their functions."

**Expected**:
- Agent selects shotgun metagenomics workflow.
- Includes metagenome-host-removal with human (GRCh38) reference.
- Recommends Kraken2/Bracken for taxonomic profiling.
- Includes metagenome-functional-profiling with HUMAnN 3 for read-based functional analysis.
- Optionally suggests assembly + binning for MAG recovery if depth is sufficient.

## Scenario 4: Ambiguous Request

**Input**: "Analyze my sequencing data."

**Expected**:
- Agent does NOT guess the pipeline.
- Asks clarifying questions: data type, organism, sequencing platform, goal.
- Does not proceed until essential information is provided.

## Scenario 5: Resume from Partial Output

**Input**: "I already have aligned and deduplicated BAMs. I want to call variants."

**Expected**:
- Agent validates BAMs have read groups, are sorted, and indexed.
- Recommends running genome-alignment-qc first to verify quality.
- Continues pipeline from genome-variant-calling step onward.
- Does not re-run alignment or preprocessing.
