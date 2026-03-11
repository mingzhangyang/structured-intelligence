# NCBI E-utilities in the AI Era: A Natural-Language Skill for Scientific Literature Retrieval and Research Update Briefing

## Abstract

Scientific progress now moves fast enough that staying current is itself a technical task. Researchers do not only need access to papers; they need repeatable ways to discover recent work, filter it by topic and time window, retrieve abstracts and metadata at scale, and convert those results into concise update briefs that can guide reading, discussion, and planning. NCBI's Entrez Programming Utilities (`E-utilities`) already provide the official API layer for this kind of literature retrieval across PubMed and other Entrez databases, but practical use still assumes familiarity with endpoint names, parameter conventions, History-server semantics, output formats, rate limits, and multi-step retrieval workflows [1-3]. This manuscript introduces `ncbi-eutilities-assistant`, a reusable skill that reframes E-utilities as an AI-mediated scientific workflow. The skill combines official API conventions, deterministic command-line wrappers, and natural-language orchestration so that users can request outcomes such as "show me the last 7 days of CRISPR progress" while preserving explicit queries, reproducible retrieval paths, and machine-readable outputs. The result is not a replacement for PubMed or E-utilities, but an interface layer that makes literature surveillance, structured review preparation, and recurring update briefs easier to operationalize across research teams.

## 1. Introduction

The scientific literature is both a knowledge base and a moving target. For many domains, especially fast-evolving ones such as genome editing, single-cell omics, AI for biology, and therapeutic engineering, the practical challenge is no longer merely whether relevant papers exist. The challenge is whether a researcher can discover, retrieve, summarize, and revisit those papers quickly enough for the information to remain operationally useful.

PubMed is one of the most important entry points for this work, and it sits within the wider Entrez ecosystem that integrates literature with sequence, gene, genome, structure, and variation resources [1,4]. Yet the moment a user moves beyond one-off manual searching in a browser, the workflow becomes more technical. Users who want repeatable retrieval pipelines must understand the E-utilities ecosystem: when to use `esearch` versus `esummary`, how `efetch` output formats differ from endpoint to endpoint, how the Entrez History server stores result sets using `WebEnv` and `query_key`, and how to structure batching without violating rate-limit guidance [2,3]. These are manageable details for experienced developers or bioinformaticians, but they remain friction for many bench scientists, trainees, interdisciplinary collaborators, and research-support teams.

In the AI era, a useful opportunity emerges. Instead of expecting every user to memorize API mechanics, a skill can encode those mechanics in a transparent, deterministic layer while allowing the user to express goals in natural language. The important point is not to hide the API. The point is to expose it through a more usable interface without sacrificing auditability.

## 2. Why E-utilities Need an Interface Layer

NCBI E-utilities are powerful precisely because they are composable. A user can search, summarize, fetch, cross-link, and batch IDs programmatically. But this composability also means the workflow is distributed across several concepts that many users do not think about naturally [2,3]:

- endpoint knowledge: knowing what `einfo`, `esearch`, `esummary`, `efetch`, `elink`, and `epost` each do
- parameter knowledge: knowing which combinations of `db`, `retmode`, `rettype`, `retmax`, `retstart`, and date filters are valid or useful
- history knowledge: knowing when to use `usehistory=y`, and how `WebEnv` plus `query_key` simplify batch retrieval
- output knowledge: knowing when JSON is available, when XML is safer, and how to turn raw records into review-ready artifacts
- operational knowledge: knowing how to include `tool`, `email`, and `api_key`, and how to stay within NCBI's usage guidance

These are not conceptual barriers to science, but they are practical barriers to workflow adoption. A scientist asking, "What happened in CRISPR this week?" is not really asking to manually construct three API calls, parse XML, and rank results. They are asking for a bounded, reproducible synthesis task.

An AI-mediated interface layer can absorb these procedural details and make them available on demand:

- "Search PubMed for CRISPR papers from the last 7 days."
- "Extract titles and abstracts into JSON."
- "Summarize the last month of base editing progress."
- "Show me the exact E-utilities requests before you run them."

This shift matters because it changes the user's interaction from endpoint assembly to intent declaration while still preserving explicit computational steps.

## 3. The `ncbi-eutilities-assistant` Skill

`ncbi-eutilities-assistant` is implemented as a local skill in this repository. It packages three layers of operational knowledge.

1. `SKILL.md`
   The skill document defines when the capability should be used, what forms of input are expected, how requests should be translated into deterministic commands, and what outputs should be returned.

2. Focused reference material
   A compact reference file summarizes the official E-utilities model, including endpoint roles, history-server usage, rate-limit guidance, and recommended retrieval patterns for PubMed-oriented workflows.

3. Deterministic Python and shell automation
   The bundled command-line wrapper exposes both low-level and high-level workflows. Low-level subcommands support official E-utilities endpoints directly:
   - `info`
   - `search`
   - `summary`
   - `fetch`
   - `link`
   - `post`

   On top of these, the skill adds higher-level PubMed workflows:
   - `pubmed-workflow`
     A multi-step retrieval path that runs `esearch`, then `esummary`, and optionally `efetch`
   - `pubmed-review`
     A literature-review extraction pipeline that parses PubMed XML into structured JSON and JSONL
   - `pubmed-update-brief`
     A recent-progress workflow that writes a concise markdown briefing alongside the raw retrieval artifacts

This structure is deliberate. The deterministic layer handles endpoint correctness and reproducibility. The AI layer handles task translation and user interaction.

## 4. Design Goals

The skill was designed around four explicit goals:

1. Preserve the official E-utilities model rather than inventing a parallel API abstraction.
2. Make multi-step PubMed retrieval reproducible for users who think in research tasks rather than endpoint names.
3. Produce machine-readable intermediate artifacts that remain useful outside the agent session.
4. Support recurring update workflows, such as weekly or monthly topic surveillance, without requiring custom scripting for each topic.

These goals matter because scientific software often fails at one of two extremes. Either it remains technically correct but operationally inaccessible, or it becomes convenient at the cost of transparency. The design of this skill aims at a middle layer: explicit enough to inspect, but compact enough to reuse.

## 5. From API Calls to Research Workflows

The main contribution of the skill is not that it wraps an API. Many scripts can do that. The contribution is that it turns an API family into reusable scientific workflows.

### 5.1 Endpoint-level control remains available

For expert users, the skill does not remove direct access to E-utilities semantics. Users can still issue requests that correspond cleanly to `esearch`, `esummary`, `efetch`, `elink`, and `epost`, inspect exact request plans with `--dry-run`, and save raw outputs for downstream processing.

This matters because scientific tooling should remain inspectable. A skill that cannot show its exact query or output path is hard to trust in regulated or high-stakes contexts.

### 5.2 Review preparation becomes deterministic

The `pubmed-review` workflow addresses a common research task: gather a bounded set of papers on a topic, retrieve their abstracts, and convert them into a structured form suitable for later analysis.

Instead of asking each user to manually combine:

1. a search query
2. a result window
3. a history-server state
4. an XML fetch
5. a custom parser

the skill provides a single reproducible workflow that emits:

- raw search output
- summary metadata
- full XML retrieval
- parsed `records.json`
- parsed `records.jsonl`

Each extracted record can include fields such as:

- PMID
- title
- abstract
- abstract sections
- journal
- publication year
- authors
- publication types
- MeSH terms
- keywords
- article IDs such as DOI

That output is directly useful for screening, clustering, downstream summarization, or integration into notebook and dashboard workflows.

### 5.3 Recent-progress briefing becomes a first-class operation

The most socially and scientifically important high-level addition is `pubmed-update-brief`. This workflow is designed for recurring surveillance questions, for example:

- What happened in CRISPR this week?
- What are the latest base editing papers this month?
- Which prime editing papers from the last 30 days should I read first?

Instead of returning only raw metadata, the workflow produces a bounded markdown briefing that includes:

- the search frame and time window
- the number of records analyzed
- repeated topical signals
- notable papers
- short abstract-derived snippets
- a watchlist of PMIDs for manual follow-up

This changes literature monitoring from an ad hoc browsing habit into a reproducible reporting artifact. In practice, this means that a query such as "CRISPR" can be turned into a weekly or monthly brief by changing only the time horizon, while preserving the same retrieval logic and output schema.

## 6. A New Interaction Model for Scientific Literature Monitoring

The skill introduces a broader pattern for AI-assisted scientific work.

### 6.1 Natural language becomes the workflow trigger

A user can begin with a sentence rather than a parameter sheet:

```text
Use $ncbi-eutilities-assistant to show me the last 7 days of CRISPR progress on PubMed and write a concise update brief.
```

or:

```text
Use $ncbi-eutilities-assistant to summarize the last 30 days of base editing research on PubMed into a markdown update brief.
```

The user specifies the research intent and time horizon. The skill supplies the endpoint choreography, file outputs, and retrieval semantics.

### 6.2 Determinism and summarization can coexist

One common concern about AI-mediated scientific interfaces is that they may blend retrieval and interpretation too opaquely. This skill takes the opposite approach. It separates deterministic retrieval from higher-level narrative organization:

- retrieval is explicit and reproducible
- intermediate files are preserved
- summaries are generated from bounded retrieved content
- the user can inspect the underlying records at any stage

This is a useful design principle for scientific AI systems more generally. The role of the model is not to replace the database. The role of the model is to make the database operationally usable.

### 6.3 Team workflows become easier to standardize

When literature updates are generated by individual habits alone, results are often inconsistent. One researcher may sort by date, another by relevance; one may read only titles, another may export CSV, another may stop after the first page. A deterministic skill reduces this variation.

Labs, review groups, translational teams, and project meetings can converge on shared routines such as:

- weekly topic surveillance
- monthly therapeutic-area briefings
- structured screening exports for downstream review
- archived markdown updates tied to explicit search windows

In this sense, the skill is not just a convenience layer. It is a coordination technology.

## 7. Implementation Characteristics

The current implementation exposes both low-level and high-level commands through a deterministic local wrapper. The low-level layer maps closely to the official endpoint families, while the higher-level layer provides three PubMed-specific compositions:

- a retrieval workflow (`pubmed-workflow`)
- a structured review extractor (`pubmed-review`)
- a recent-progress brief generator (`pubmed-update-brief`)

The high-level workflows use the Entrez History server to avoid brittle one-record-at-a-time retrieval patterns and to keep the search, summary, and fetch phases connected through `WebEnv` and `query_key` [2,3]. This design is important for reproducibility because it preserves a clear lineage from query term to retrieved record set.

The implementation also uses explicit output files rather than ephemeral in-memory summaries alone. Typical outputs include raw `esearch` and `esummary` responses, PubMed XML from `efetch`, structured JSON and JSONL records, and a markdown briefing. This file-oriented design supports later reuse in notebooks, dashboards, downstream AI summarization, or collaborative review.

## 8. Methods

### 8.1 Skill architecture

The skill is implemented as a local bundle composed of four elements:

- a `SKILL.md` policy document that defines intended use, inputs, outputs, and operating limits
- provider-facing metadata for AI tool discovery
- a focused reference file summarizing official E-utilities usage patterns
- a deterministic command-line wrapper that executes the retrieval workflows

The command-line wrapper is the operational core. It translates natural-language-level tasks into explicit endpoint calls and workflow steps while preserving access to low-level parameter control.

### 8.2 Retrieval model

The implementation exposes two layers of interaction:

1. Endpoint-level commands for `einfo`, `esearch`, `esummary`, `efetch`, `elink`, and `epost`
2. Higher-level PubMed workflows that compose these endpoints into reusable retrieval patterns

For multi-step PubMed workflows, the implementation uses `esearch` with `usehistory=y`, followed by `esummary` and `efetch` operating on the returned `WebEnv` and `query_key` values. This design reduces the need for brittle manual ID passing and aligns with the intended Entrez History-server model [2,3].

### 8.3 Output generation

The higher-level PubMed workflows are file-oriented by design. Instead of returning only transient console summaries, they emit durable artifacts such as:

- raw `esearch` and `esummary` responses
- PubMed XML from `efetch`
- parsed JSON and JSONL records
- markdown update briefs
- a manifest describing counts, identifiers, and output paths

This output strategy was chosen to support downstream reuse in notebooks, dashboards, screeners, AI summarizers, or team review pipelines.

### 8.4 Briefing strategy

The `pubmed-update-brief` workflow generates a bounded markdown draft using deterministic heuristics over the retrieved records. The current implementation derives:

- a search frame summary
- repeated topical signals from titles and indexed terms
- notable-paper entries with PMID, journal, year, author summary, and an abstract-derived snippet
- a watchlist of PMIDs for manual follow-up

This briefing layer is intentionally lightweight. It is meant to provide a reproducible first-pass update artifact rather than a substitute for full expert evaluation.

### 8.5 Validation strategy

The skill has been validated at three levels:

- static validation of repository structure and skill metadata
- command-level dry-run validation to inspect generated request plans without network calls
- local mock-server smoke tests to verify multi-step workflow execution, intermediate-file generation, structured record extraction, and markdown brief creation

The mock-server tests are particularly useful because they allow end-to-end validation of workflow logic without depending on live external services during development.

## 9. What Changes in the AI Era

The AI era changes where labor occurs in scientific information work.

Previously, much of the labor was manual procedural glue:

- translating a question into a search string
- remembering endpoint names
- passing IDs between requests
- parsing outputs into usable form
- rewriting findings into human-readable notes

With a skill like `ncbi-eutilities-assistant`, much of that glue is encoded once and reused many times. This does not eliminate the need for judgment. Researchers still need to assess study quality, novelty, relevance, and experimental rigor. But it reduces the amount of mechanical work that stands between a question and a tractable reading list or briefing document.

This matters for scientific communities because the bottleneck in knowledge use is often not access alone. It is structured access, repeated access, and quickly interpretable access.

## 10. Limitations and Guardrails

This approach improves workflow usability, not the underlying validity of scientific claims.

Several limits remain:

- the skill depends on live access to NCBI E-utilities
- NCBI usage guidance and endpoint behavior may evolve over time
- PubMed is broad but not exhaustive; preprint servers and domain-specific sources may still be needed for the earliest signals
- `EFetch` formats and endpoint options remain database-specific
- update briefs are retrieval-driven summaries, not substitutes for critical reading

There are also methodological limitations. A weekly or monthly brief is only as good as its query design. A narrow query may miss adjacent work; a broad query may mix unrelated subfields. Likewise, abstract-level extraction is useful for triage, but full-text interpretation often remains necessary for serious evaluation.

The operational limits are also concrete. NCBI recommends that API users include `tool` and `email`, and that traffic remain within published request-rate guidance unless an API key is used [2,3]. A workflow tool that ignores these constraints may be convenient in the short term but unsound in sustained use. For these reasons, the skill is best understood as a high-leverage interface layer rather than an autonomous scientific reviewer.

This point also matters institutionally. `ncbi-eutilities-assistant` is an independent, unofficial interaction layer around NCBI's public E-utilities and related PubMed workflows. It does not claim ownership of NCBI services, records, or documentation, and it should not be interpreted as an endorsed NCBI product. Users remain responsible for complying with upstream usage guidance, attribution norms, and applicable terms for the original resources [1-4].

## 11. Availability

`ncbi-eutilities-assistant` is implemented as a reusable local skill within the Structured Intelligence repository, which is publicly available at `https://github.com/Scientific-Tooling/structured-intelligence` (accessed March 11, 2026). The repository is distributed under the MIT License. The manuscript source and skill bundle described here are available in that repository, including:

- skill definition and usage guidance
- deterministic retrieval scripts
- PubMed review and update-brief workflows
- installation commands for Codex and Claude Code environments

Within the repository, the relevant materials are located under:

- `skills/ncbi-eutilities-assistant/`
- `docs/ncbi-eutilities-assistant-manuscript.md`

The skill is intended for local use in AI-assisted coding and research environments that support skill discovery from filesystem bundles. At the repository level, the materials can be cloned, installed with the bundled installation scripts, and inspected as plain-text workflow assets. Users citing the software should reference the repository URL together with an access date and, where relevant, the specific skill path documented in this manuscript. The repository's implementation should be understood as an independent, unofficial AI interface layer rather than a redistribution of, or substitute for, the original NCBI services and materials.

## 12. Conclusion

`ncbi-eutilities-assistant` demonstrates how official scientific APIs can be translated into reusable AI-era workflow components. By combining E-utilities semantics, deterministic retrieval logic, structured intermediate outputs, and natural-language invocation, the skill makes PubMed surveillance and literature extraction more accessible without making them opaque.

Its most useful contribution may be cultural rather than purely technical. It reframes the act of "keeping up with the literature" from an informal, individually improvised activity into something that can be operationalized, shared, repeated, and inspected. A scientist should be able to ask what changed in CRISPR this week and receive not only a list of papers, but a reproducible path from question to briefing.

That is the broader promise of skills for science. They do not replace databases, journals, or expert judgment. They connect them to the language and workflow habits that working researchers already have. In that sense, the future of scientific information access may not be just search, and not just conversation. It may be disciplined, inspectable, skill-based orchestration.

## References

1. Cooper P, Romiti M. Entrez Help. In: Entrez Help [Internet]. Bethesda (MD): National Center for Biotechnology Information (US); 2005-. Updated June 27, 2024. Available from: https://www.ncbi.nlm.nih.gov/books/NBK3837/
2. National Center for Biotechnology Information (US). Entrez Programming Utilities Help [Internet]. Bethesda (MD): National Center for Biotechnology Information (US); 2010-. Available from: https://www.ncbi.nlm.nih.gov/books/NBK25501/
3. Sayers E. The E-utilities In-Depth: Parameters, Syntax and More. In: Entrez Programming Utilities Help [Internet]. Bethesda (MD): National Center for Biotechnology Information (US); 2010-. Updated November 30, 2022. Available from: https://www.ncbi.nlm.nih.gov/books/NBK25499/
4. Sayers EW, Cavanaugh M, Clark K, Pruitt KD, Sherry ST, Yankie L, et al. Database resources of the National Center for Biotechnology Information in 2026. Nucleic Acids Res. 2026. doi:10.1093/nar/gkaf1060. Available from: https://academic.oup.com/nar/advance-article-abstract/doi/10.1093/nar/gkaf1060/8378181
