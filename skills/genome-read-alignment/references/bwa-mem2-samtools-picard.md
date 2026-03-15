# BWA-MEM2 / samtools / Picard MarkDuplicates Reference

## BWA-MEM2 — Index Building

```bash
bwa-mem2 index ref.fa
```

Produces 5 index files that must all be present alongside the reference:

| File | Purpose |
|------|---------|
| `ref.fa.0123` | BWT compressed index |
| `ref.fa.amb` | Ambiguous base positions |
| `ref.fa.ann` | Sequence annotations |
| `ref.fa.bwt.2bit.64` | BWT in 2-bit packed format |
| `ref.fa.pac` | Packed forward sequence |

If any index file is missing, BWA-MEM2 will fail with a cryptic "can't open" error. Re-run `bwa-mem2 index`.

## BWA-MEM2 — Alignment

```bash
bwa-mem2 mem \
  -t 16 \
  -R "@RG\tID:sample1_L001\tSM:sample1\tPL:ILLUMINA\tLB:lib1\tPU:FLOWCELLID.L001" \
  -M \
  ref.fa R1.trimmed.fastq.gz R2.trimmed.fastq.gz \
  | samtools sort -@ 8 -m 2G -o sample1.sorted.bam
```

### Key alignment flags

| Flag | Meaning |
|------|---------|
| `-t` | Threads |
| `-R` | Read group header line (required by GATK) |
| `-M` | Mark shorter split hits as secondary (SAM flag 0x100); required for Picard compatibility |
| `-K` | Process this many bases per batch (reproducibility across thread counts) |

## Read Group Fields Required by GATK

GATK will refuse to process BAMs missing read groups. All four fields below are mandatory:

| Field | Description | Example |
|-------|-------------|---------|
| `ID` | Unique identifier per lane/run | `sample1_FLOWCELL_L001` |
| `SM` | Sample name (matched to VCF sample column) | `NA12878` |
| `PL` | Sequencing platform | `ILLUMINA` |
| `LB` | Library prep identifier | `WGS_lib1` |
| `PU` | Platform unit: `<flowcell>.<lane>` (ideally) | `HNJWVDRXY.1` |

## samtools sort

```bash
samtools sort \
  -@ 8 \          # additional threads (total = 9)
  -m 2G \         # memory per thread
  -n \            # name-sort (omit for coordinate sort, which is the default)
  -o output.bam \
  input.bam
```

Coordinate-sorted BAM is required for indexing and most downstream tools. Name-sorted BAM is needed only for tools that process read pairs together (e.g., some duplicate markers, fixmate).

## samtools index

```bash
samtools index -@ 8 sample.sorted.bam
# produces sample.sorted.bam.bai
```

Requires a coordinate-sorted BAM. The `.bai` index must be in the same directory as the BAM for tools that auto-discover it.

## Picard MarkDuplicates

```bash
picard MarkDuplicates \
  -I sample.sorted.bam \
  -O sample.markdup.bam \
  -M sample.markdup.metrics.txt \
  --REMOVE_DUPLICATES false \
  --VALIDATION_STRINGENCY SILENT \
  --OPTICAL_DUPLICATE_PIXEL_DISTANCE 2500
```

### Key options

| Option | Recommendation |
|--------|---------------|
| `REMOVE_DUPLICATES` | `false` — mark with flag 0x400 but keep records; callers can filter |
| `VALIDATION_STRINGENCY` | `SILENT` — avoids failures on minor SAM spec deviations |
| `OPTICAL_DUPLICATE_PIXEL_DISTANCE` | `2500` for patterned flowcells (NovaSeq, HiSeq X); `100` for non-patterned |
| `METRICS_FILE` | Always specify; contains percent duplication and estimated library size |

After MarkDuplicates, re-index the output BAM with `samtools index`.

## Common Gotchas

- **All 5 BWA-MEM2 index files must be present.** Partial index builds (e.g., interrupted runs) cause alignment failures.
- **Missing read groups cause GATK to fail.** Always include `-R` at alignment time; adding read groups post-hoc with Picard AddOrReplaceReadGroups is possible but slower.
- **`-M` flag is necessary for Picard compatibility.** Without it, split-read supplementary alignments may confuse Picard's duplicate detection logic.
- **Picard requires Java 17+.** Running with Java 11 may produce module access warnings or failures on newer Picard versions.
- **OPTICAL_DUPLICATE_PIXEL_DISTANCE must match the flowcell type.** Using 100 on NovaSeq data will dramatically underestimate optical duplicates.
- **samtools sort `-@` sets additional threads**, so `-@ 8` uses 9 total. Account for this when allocating job resources.
