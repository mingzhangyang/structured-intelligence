# RPS-BLAST in the AI Era: A Natural-Language Skill for CDD Domain Annotation

## Abstract

`rpsblast` is a mature and valuable tool for conserved-domain annotation, but its practical use still assumes command-line fluency, familiarity with NCBI's Conserved Domain Database (CDD) file layout, and knowledge of the `rpsblast -> rpsbproc` processing chain [1-4]. Those assumptions create avoidable friction for biologists, research assistants, and interdisciplinary users who understand the analysis goal but do not routinely operate low-level bioinformatics tooling. This manuscript introduces `rpsblast-assistant`, a reusable skill that reframes `rpsblast` as an AI-mediated workflow. Instead of asking users to memorize download URLs, file naming conventions, archive formats, and output parsing rules, the skill lets users express intent in natural language while an AI agent translates that intent into validated setup, download, execution, and interpretation steps. The result is not a replacement for `rpsblast`, but a new interface layer around it: one that preserves the underlying NCBI workflow while making it easier to adopt, audit, and operationalize.

## 1. Introduction

The command line has always offered precision, but precision often comes at the cost of accessibility. This tradeoff is especially visible in bioinformatics, where powerful tools are frequently packaged as a set of executables, archives, index files, and loosely coupled preprocessing or postprocessing utilities. `rpsblast` is a clear example. The tool is highly capable, but running it correctly requires more than a single binary. Users must know where to obtain the CDD databases, how to unpack them, which annotation files are needed by `rpsbproc`, how to choose the right executable for protein or nucleotide queries, and which output format is compatible with downstream processing [1-3].

For experienced practitioners, this setup is normal. For new users, it is a barrier. Many do not need to become shell experts; they need to answer a biological question, inspect a domain architecture, or annotate a FASTA file. In the AI era, that distinction matters. Large language models and code agents can now function as interface translators between user intent and deterministic tooling. The opportunity is not to make `rpsblast` "automatic" in a vague sense, but to encode a correct operational playbook so an AI agent can execute it reliably on behalf of the user.

## 2. Why `rpsblast` Needs an Interface Layer

The classic local workflow around `rpsblast` contains several kinds of hidden knowledge [1-4]:

- acquisition knowledge: where to download BLAST+ executables, CDD databases, and `rpsbproc` assets
- filesystem knowledge: where those files should live and what database prefix `-db` should point to
- execution knowledge: when to use `rpsblast` versus `rpstblastn`, what E-value to choose, and why `-outfmt 11` matters
- interpretation knowledge: how to understand the intermediate ASN.1 archive and the final `rpsbproc` tabular output

These are not difficult concepts individually, but they are easy to get wrong in combination. Small mistakes are common: pointing `-db` at a directory instead of a prefix, forgetting to download annotation files, producing a text BLAST report that `rpsbproc` cannot read, or treating the final `.out` file as an unstructured spreadsheet dump rather than a structured report with comments and data sections.

An AI-mediated interface can absorb this hidden knowledge and expose the tool in the language users already think in:

- "Help me download the minimal CDD database."
- "Check whether my local setup is complete."
- "Run this FASTA against CDD and explain the output."
- "What part of `sequence.out` is the real tabular data?"

This is a different mode of software use. The user specifies intent; the agent supplies parameterization, file choreography, and validation.

## 3. The `rpsblast-assistant` Skill

`rpsblast-assistant` is implemented as a local skill in this repository. It packages three layers of operational knowledge:

1. `SKILL.md`
   A concise policy and workflow document describing when the skill should be used, what inputs it expects, how it translates natural-language requests into concrete actions, and what outputs it must return.

2. Reference material
   A focused reference document captures the essential public workflow for local `rpsblast` and `rpsbproc` usage: official download sources, expected directory layout, the canonical execution pattern, and the structure of the final output.

3. Deterministic shell automation
   The bundled `scripts/run.sh` script provides subcommands for:
   - `sources`: print official acquisition URLs
   - `download`: fetch and extract CDD databases and annotation files
   - `check`: verify local setup completeness
   - `run`: execute the `rpsblast -> rpsbproc` pipeline

This design is deliberate. The language model is used where interpretation and user interaction are needed; the shell script is used where consistency and repeatability matter.

## 4. Design Goals

The skill was designed around four explicit goals:

1. Preserve the official standalone RPS-BLAST plus `rpsbproc` workflow rather than invent a parallel search model.
2. Make CDD setup and execution reproducible for users who think in annotation tasks rather than low-level command flags.
3. Expose exact commands, file paths, and output artifacts so that the workflow remains inspectable.
4. Reduce common operational mistakes without hiding the underlying bioinformatics method.

These goals are important because bioinformatics tooling often fails at one of two extremes: it is either technically correct but operationally inaccessible, or it is easy to use only because important details are hidden. `rpsblast-assistant` aims at a middle layer: explicit enough to audit, compact enough to reuse.

## 5. From Command Invocations to Annotation Workflows

The main contribution of the skill is not that it wraps a command-line tool. Many shell scripts can do that. The contribution is that it turns a brittle multi-file setup plus execution pattern into a reusable annotation workflow.

### 5.1 Low-level control remains available

For experienced users, the skill does not remove direct access to the underlying standalone workflow. Users can still inspect acquisition sources, choose database sets, override thresholds, point to explicit database prefixes, and see the exact command lines used for both `rpsblast` and `rpsbproc`.

This matters because scientific tooling should remain inspectable. A wrapper that hides where files were downloaded, which binary was selected, or how post-processing was triggered is difficult to trust in collaborative or regulated settings.

### 5.2 Setup and execution become deterministic

The common standalone workflow requires a user to coordinate:

1. binary acquisition
2. database download
3. annotation-file download
4. correct database-prefix selection
5. ASN.1 archive output generation
6. `rpsbproc` post-processing

The skill collapses these into a bounded sequence of deterministic operations with explicit file outputs and pre-flight checks. Instead of rediscovering the same operational details each time, the user can reuse a stable path from raw FASTA input to processed domain-annotation output.

### 5.3 Output interpretation becomes a first-class operation

The workflow does not stop at execution. The resulting artifacts remain available for explanation and downstream use: the ASN.1 archive captures the machine-oriented intermediate result, while the processed `.out` file becomes the human-readable reporting layer. Treating interpretation as part of the workflow shortens the distance between computation and understanding.

## 6. A New Interaction Model for Bioinformatics Tools

The skill introduces a practical pattern for using legacy or expert-oriented scientific software in an AI environment.

### 6.1 Natural language becomes the front end

Instead of manually assembling commands, users can ask an AI agent for outcomes:

```text
Use $rpsblast-assistant to download the minimal CDD database and rpsbproc annotation files into ./db and ./data.
```

or:

```text
Use $rpsblast-assistant to run rpsblast on ./sequence.fasta against ./db/Cdd with E-value 0.01 and then post-process with rpsbproc.
```

The agent maps these requests to explicit shell operations, while still exposing the exact command lines it runs. This matters because natural language should improve usability without erasing auditability.

### 6.2 The agent becomes a workflow governor

A useful AI interface does more than generate commands. It should also prevent common failure modes. In this skill, the agent is expected to:

- select `rpsblast` for protein queries and `rpstblastn` for nucleotide queries
- default to the article's worked local threshold of `0.01` unless told otherwise
- force ASN.1 archive output when `rpsbproc` is required
- stop early if databases or annotation files are missing
- explain the difference between intermediate and final outputs

This is a subtle but important shift. The model is not acting as an oracle; it is acting as a guardrailed operator.

### 6.3 Team workflows become easier to standardize

When setup and execution depend on individual shell knowledge, results are often inconsistent. One user downloads the full database, another only the minimal set; one forgets the annotation bundle, another produces a plain-text BLAST report that cannot be post-processed. A deterministic skill reduces this variation.

Labs, training groups, and collaborative annotation projects can converge on shared routines such as:

- standardized local setup checks
- reproducible database acquisition for a given project
- explicit archival of intermediate ASN.1 outputs
- shared interpretation of processed domain-annotation reports

In this sense, the skill is not just a convenience layer. It is a coordination technology for expert-oriented bioinformatics tooling.

## 7. Implementation Characteristics

The current implementation exposes a deterministic shell wrapper around the standalone CDD workflow. Its main functions are:

- `sources`: print acquisition URLs for binaries, databases, and annotation files
- `download`: retrieve and unpack the required CDD and `rpsbproc` assets
- `check`: verify local setup completeness
- `run`: execute `rpsblast` or `rpstblastn`, then optionally `rpsbproc`

This design has two important implementation properties. First, the workflow is file-oriented rather than ephemeral. Users receive explicit databases, annotation files, ASN.1 outputs, and processed flat files. Second, the implementation enforces the format dependencies that matter most, especially the requirement that `rpsbproc` consume ASN.1 archive output from standalone RPS-BLAST [1].

The result is a tool that remains close to the documented NCBI workflow while becoming easier to invoke through natural-language agents.

## 8. Methods

### 8.1 Skill architecture

The skill is implemented as a local bundle composed of:

- a `SKILL.md` policy document
- provider-facing metadata for AI tool discovery
- a focused reference file for standalone RPS-BLAST and `rpsbproc`
- a deterministic shell script that executes the operational workflow

The shell script is the execution core. It is intentionally simple and explicit, because the purpose of the skill is not to replace the underlying programs but to make their correct use more reusable.

### 8.2 Retrieval and processing model

The implementation follows the standalone workflow described for local CDD annotation [1]:

1. obtain the BLAST+ executables containing `rpsblast` or `rpstblastn`
2. obtain the `rpsbproc` utility
3. download the relevant preformatted CDD databases
4. download the domain annotation files needed by `rpsbproc`
5. run RPS-BLAST in ASN.1 archive mode
6. run `rpsbproc` on the ASN.1 output

The skill wrapper does not change the underlying scientific method. It standardizes command construction, file layout, and pre-flight validation.

### 8.3 Output model

The operational outputs are explicit files rather than hidden intermediate state. Depending on the task, these can include:

- downloaded database archives
- unpacked CDD database files
- unpacked annotation files
- raw ASN.1 output from `rpsblast` or `rpstblastn`
- processed `.out` files from `rpsbproc`

This file-oriented design supports later parsing, sharing, and reproducibility checks.

### 8.4 Validation strategy

The skill has been validated at the level of repository structure, command construction, and local workflow logic. The most important validation targets are:

- correct acquisition URLs
- correct database and data-file expectations
- correct `-outfmt 11` enforcement when `rpsbproc` is required
- correct differentiation between protein and nucleotide query modes
- correct reporting of generated file paths and output types

These validation points are especially useful because many practical failures in standalone RPS-BLAST use are operational rather than algorithmic.

## 9. What Changes in the AI Era

The AI era does not eliminate the need for scientific rigor. It changes where complexity lives.

Previously, complexity lived mostly in the user's head. The user had to remember URLs, flags, formats, and file relationships. With skills like `rpsblast-assistant`, complexity is moved into a reusable operational layer:

- the workflow becomes inspectable
- the defaults become explicit
- the tool becomes easier to delegate
- onboarding becomes faster
- reproducible use becomes easier to standardize across a lab or team

This is especially important for mixed teams. A computational biologist may already know how to use `rpsblast`, but a bench scientist, project manager, trainee, or collaborator may not. A natural-language skill narrows that gap without flattening the underlying method into a black box.

## 10. Limitations and Guardrails

This approach improves usability, not biological validity. Several constraints remain:

- users still need the official NCBI binaries and CDD assets
- local network availability still matters for download steps
- AI agents can choose defaults, but they cannot remove the need for judgment about query quality, threshold selection, or downstream interpretation
- version changes in BLAST+, CDD, or `rpsbproc` may alter behavior or output details

The operational limits are also concrete. Standalone CDD annotation depends on exact file relationships among executables, databases, annotation resources, and archive outputs. If these relationships are obscured, users can produce output that appears valid but is not post-processable. Accordingly, the skill is designed to expose commands, file paths, and output types rather than hide them. The goal is assisted operation, not opaque automation.

## 11. Availability

`rpsblast-assistant` is implemented as a reusable local skill within the Structured Intelligence repository. The manuscript source and skill bundle are available in this repository, including:

- skill definition and usage guidance
- deterministic download, validation, and execution scripts
- references for standalone RPS-BLAST and `rpsbproc`
- installation commands for Codex and Claude Code environments

Within the repository, the relevant materials are located under:

- `skills/rpsblast-assistant/`
- `docs/rpsblast-assistant-manuscript.md`

The skill is intended for local use in AI-assisted coding and research environments that support skill discovery from filesystem bundles.

## 12. Conclusion

`rpsblast-assistant` demonstrates a broader pattern for scientific computing in the AI era. Mature command-line tools do not need to be rewritten to benefit from modern AI systems. Instead, they can be wrapped in disciplined skills that combine public reference knowledge, deterministic scripts, and natural-language orchestration. In this model, `rpsblast` remains the engine, but the user experience changes dramatically. A task that once required detailed procedural memory can now begin with a sentence.

That shift matters. It lowers adoption barriers, reduces setup mistakes, and makes proven bioinformatics workflows available to a wider range of researchers without compromising the underlying computational method. The future of scientific tooling may not be purely graphical or purely conversational. It may be skill-based: language on the outside, validated commands underneath.

## References

1. Yang M, Derbyshire MK, Yamashita RA, Marchler-Bauer A. NCBI's Conserved Domain Database and Tools for Protein Domain Analysis. Curr Protoc Bioinformatics. 2020;69(1):e90. doi:10.1002/cpbi.90. Available from: https://pmc.ncbi.nlm.nih.gov/articles/PMC7378889/
2. Madden T. BLAST Command Line Applications User Manual [Internet]. Bethesda (MD): National Center for Biotechnology Information (US); 2008-. Available from: https://www.ncbi.nlm.nih.gov/books/NBK279690/
3. National Center for Biotechnology Information. NCBI Conserved Domain Database (CDD) Help. Available from: https://www.ncbi.nlm.nih.gov/Structure/cdd/cdd_help.shtml
4. Sayers EW, Cavanaugh M, Clark K, Pruitt KD, Sherry ST, Yankie L, et al. Database resources of the National Center for Biotechnology Information in 2026. Nucleic Acids Res. 2026. doi:10.1093/nar/gkaf1060. Available from: https://academic.oup.com/nar/advance-article-abstract/doi/10.1093/nar/gkaf1060/8378181
