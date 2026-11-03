# Scout — Engineering Roadmap

> **The thesis.** Most RAG systems retrieve for *every* query, blindly. **Scout is an adaptive retrieval agent (agentic RAG)**: it decides *whether* to retrieve, *what* to search for, *where* to look — the user's own documents or the open web — and *how much* to retrieve, judging its own results and looping to refine, then **compressing what it finds to fit the budget** — and it **proves, with numbers, that this saves cost without sacrificing answer quality.**
>
> It is an **agent whose job is retrieval** — not a general-purpose agent. Every "agentic" behaviour (routing, self-critique, web traversal, compression) exists to retrieve *better*. Features that would make retrieval just one tool among many (arbitrary tool-calling, code execution, sub-agents) are out of scope (§8) — that line is what keeps Scout focused and defensible.
>
> This is a living document: check items off as PRs land. "Done" = the acceptance criteria are demonstrably true.

---

## 1. What "solid" means here

A reviewer (recruiter, staff engineer, researcher) should be able to open the repo and, in five minutes, see:

1. **A clear problem and a clear claim** — stated in the README's first paragraph.
2. **Evidence the claim is true** — an ablation table with real numbers on a recognized benchmark.
3. **Correct, readable engineering** — a tested core, typed, linted, with the agentic loop actually doing what it says.
4. **Production instincts** — observability, caching, graceful degradation, CI, a working demo.
5. **Honesty** — documented limitations and failure cases, not just the happy path.

If any of these five is missing, the project is a demo, not a portfolio piece.

---

## 2. Current snapshot

**Solid foundation already in place:**
- UI-free, testable core (`rag_core.py`) cleanly separated from the marimo UI (`app.py`).
- Adaptive pipeline (`judge_query → rewrite_query → retrieve → judge_retrieved → generate`) with JSON fallbacks — the agentic loop's skeleton is **already built**.
- DuckDB VSS/HNSW vector store, sentence-aware chunking, batched Ollama embeddings.
- Runnable via `uv`; unit tests for parsing/fallbacks; CI (pytest); Dockerfile + HF Spaces scaffold.

**The gap in one sentence:** the loop *claims* to be adaptive and self-critiquing, **nothing measures whether it helps**, and it only reads a fixed Wikipedia corpus. This roadmap fixes the correctness, proves the claim, and extends the agent to the user's own documents, the open web, and context compression.

---

## 3. Guiding principles

1. **Measure the thesis.** "Adaptive" is a hypothesis until an ablation proves it. Numbers go in the README.
2. **Correct before measured.** Fix the loop bugs first — never publish numbers for a system doing the wrong thing.
3. **Depth over breadth.** Every addition must strengthen the *retrieval* thesis or it doesn't ship (§8 is the contract).
4. **Local & correct before live & messy.** The user-document path and eval come before web traversal.
5. **Keep the core UI-free and testable.** New capability lands in importable modules; the UI only orchestrates.
6. **Reproducible by a stranger.** Pinned seeds, one-command eval, documented models/hardware.

---

## PART A — Foundation (correctness + proof)

### Milestone 1 — Make the engine *correct*

The agentic loop has real bugs that must be fixed before any honest measurement.

- [ ] **Accumulate evidence across refine rounds.** `app.py` resets `docs = []` each round, discarding earlier good hits — so the refine loop *loses* context instead of adding to it. Accumulate + dedupe across rounds.
- [ ] **Global rerank before truncation.** Merge all hits across the N sub-queries, sort by cosine distance globally, *then* take top-K. Today it feeds the first-K-after-dedup.
- [ ] **Structured LLM outputs.** Replace the regex `_extract_json` with Ollama's `format=`/JSON-schema constrained decoding for `judge_query`, `rewrite_query`, `judge_retrieved`. Keep the fallbacks as a backstop.
- [ ] **Integration test of the loop** with a fake retriever + fake LLM: routing short-circuits correctly, refine accumulates docs, loop always terminates.

**Acceptance:** the refine loop demonstrably grows its evidence set across rounds; final context is the globally-top-K by similarity; an integration test locks the control flow; JSON parsing no longer depends on a regex.

### Milestone 2 — Prove it works *(the headline)*

Measure the thesis on **recognized benchmarks** and publish the result. (Pairs with Milestone 7 — tracing supplies the cost numbers.)

- [ ] **Benchmarks that stress the two claims:** a **HotpotQA** subset (multi-hop → justifies the refine loop) + a routing-stress set (answerable factual Qs mixed with chit-chat/math/reasoning → tests `judge_query`).
- [ ] **Retrieval metrics:** recall@k, MRR, nDCG vs gold passages.
- [ ] **Answer metrics:** faithfulness/groundedness + answer-relevance (RAGAS-style or local LLM-judge).
- [ ] **Cost metrics:** LLM calls, tokens, wall-clock latency per query.
- [ ] **The ablation** (the money table): `no-RAG` vs `naive always-retrieve` vs `adaptive-routing` vs `adaptive + refine loop`. Quality **and** cost for each.
- [ ] **Error analysis:** 3–5 concrete failure cases and what they reveal.
- [ ] **One command, seeded, reproducible:** `uv run python -m eval` → the table. Publish it in the README; backfill the real numbers into the CV bullets.

**Acceptance:** a reproducible command produces an ablation table on a named benchmark showing adaptive routing cutting LLM calls at equal answer quality, and the refine loop improving groundedness on multi-hop questions — with failure cases documented.

---

## PART B — Agentic capabilities (the electives)

Three electives chosen because they **share the retrieval pipeline** and reinforce each other — one system, three facets — rather than opening new, unshared axes.

### Milestone 3 — User-provided documents *(Elective: "adaptive RAG over user data")*

Let Scout retrieve over the user's **own** documents, not just Wikipedia.

- [ ] **Ingestion for `.txt` and `.pdf`** — PDF via text extraction (`pypdf`-style). **Text only — no images/OCR** (that would cross into the multimodal/VLM elective, which is out of scope).
- [ ] **Upload / point-at-a-folder** in the UI; build or extend the DuckDB store from user docs, reusing `chunk_text` + `embed_many` + the HNSW index. Keep ingestion idempotent.
- [ ] **Corpus selection** — query the user's docs (and/or the bundled corpus); each chunk carries provenance (source filename) for citations.

**Acceptance:** a user drops in a PDF and a text file, Scout indexes them, and answers a question grounded in them with correct source citations; re-ingesting the same files is a no-op.

### Milestone 4 — Context management: summarization + isolation *(Electives: "adaptive RAG summarization" + "intelligent context management")*

Deepens retrieval and is a **two-for-one**: the summarization the adaptive-RAG elective requires *is* the compression the context-management elective requires. Build it once.

- [ ] **Context compression / summarization** — compress retrieved chunks before they reach the generator (filter + summarize to the relevant spans). Measure token reduction **and** faithfulness impact in the Milestone 2 eval.
- [ ] **Context isolation** — keep each sub-query's retrieved context isolated during the refine loop, merged only at generation, so one sub-query's noise can't pollute another's.

**Acceptance:** compression reduces context tokens by a measurable % at equal-or-better faithfulness (shown in the eval); isolation is demonstrated to prevent cross-contamination between sub-queries.

### Milestone 5 — Agentic web retrieval *(Elective: "self-controlled web search + traversal")*

The headline differentiator: the **same loop**, escalated to the open web.

- [ ] **Web retriever** — search *and* fetch-and-read actual pages (traverse to the page and extract its content — beyond snippet results), as an alternative retrieval backend.
- [ ] **Routing generalises** — the router decides **direct / local-corpus / web**, and `judge_retrieved` can **escalate local → web** when the local corpus is insufficient.
- [ ] **Robustness** — timeouts, rate limits, fetch/parse failures, polite crawling; graceful fallback when the web is unavailable.
- [ ] **Eval the decision, not the answer** — measure routing accuracy (did it correctly choose web when local lacked the answer?), since live web answers are non-deterministic.

**Acceptance:** a question unanswerable from the local corpus triggers a web search that fetches and reads a real page and grounds the answer with the source URL; routing accuracy is measured and reported.

---

## PART C — Hardening & shipping

### Milestone 6 — Robustness & efficiency

- [ ] **Reranking** — cross-encoder (or MMR for diversity) on top of cosine retrieval; should move the Milestone 2 numbers.
- [ ] **Caching** — query embeddings and (optionally) retrieval results; measure the hit-rate / latency win.
- [ ] **Guardrails** — explicit "I don't know / not in context" on weak retrieval (distance threshold) instead of hallucinating.
- [ ] **Config consolidation** — one `Config` dataclass/module; kill the `N_ARTICLES` drift (`rag_core.py`=2000 vs `app.py`=1000) and scattered magic numbers.
- [ ] **Graceful degradation** — deliberate, tested behaviour when Ollama/a model/the web is unavailable.

**Acceptance:** reranking is in the pipeline and reflected in eval numbers; a cold vs warm query shows measurable cache benefit; weak-retrieval queries get an honest "not found."

### Milestone 7 — Observability *(start alongside Milestone 2)*

- [ ] **Per-request trace object** — stage, latency, token counts, routing decision (direct/local/web), # refine rounds, chunks retrieved — for every query.
- [ ] **Structured logging** (JSON lines) the eval harness aggregates for its cost column.
- [ ] **Surface it in the UI** — extend the existing streamed-reasoning view to show the trace, making the *adaptive* behaviour visible in the demo.

**Acceptance:** every query emits a structured trace; the UI visibly shows *why* a query was routed/refined/escalated; the eval reads traces for cost metrics.

### Milestone 8 — Shippable & legible

- [ ] **CI rigor** — add `ruff` (lint) + `mypy` (types) + coverage to the pytest workflow.
- [ ] **Packaging / entry point** — a clean console entry (`uvx`-installable or `uv run scout`) so a stranger runs it in one command.
- [ ] **Fix the live demo** — the Dockerfile claims `rag.duckdb` ships via Git LFS, but it's gitignored with no LFS configured, so the HF free CPU tier would download + embed on boot and time out. Commit the store via real Git LFS, bake it at build, or prebuild in the Dockerfile. **Verify the link actually boots** (or ship a recorded demo).
- [ ] **README as the front door** — problem → claim → ablation table → architecture diagram → how to reproduce → **documented limitations**; short ADR-style notes on key decisions (why DuckDB, why routing-before-retrieval, why local).
- [ ] **Demo artifact** — a GIF/short video: a simple query skips retrieval; a hard query triggers the refine loop; an out-of-corpus query escalates to the web — all with the live trace visible.

**Acceptance:** CI green on tests + lint + types; one-command run for a stranger; a working (or recorded) demo link; a README that states the claim, proves it, and admits its limits.

---

## 8. Out of scope — and *why* (deliberate cuts)

These electives would make retrieval just one tool among many, turning Scout from a focused **agentic RAG** system into a general-purpose agent — a different, unfocused, harder-to-defend project. Cut on purpose:

| Cut elective | Why it doesn't serve Scout's thesis |
|--------------|-------------------------------------|
| Extensible user tool-calling | Generic agent feature; user-provided *shell* tools drag in the code-sandbox burden as a dependency. |
| Sub-agent deployment (async) | Orchestration axis orthogonal to retrieval; large concurrency lift. |
| Secure code execution / sandbox | A whole separate systems project; retrieval is not involved. |
| Preference optimization (DPO/RLHF + LoRA) | A separate ML-training pipeline; about generation, not retrieval. |
| Multimodal ingestion (Vision+Language model) | Requires a different model stack; PDF-as-*text* (Milestone 3) stays on the right side of this line. |
| Concurrent multi-user support | Backend/infra, not thesis. |
| Advanced prompt caching (H2O) | H2O is KV-cache eviction *inside the inference engine*; **impossible on Ollama's HTTP API** without replacing the serving layer. |

## 9. Optional stretch (only once Parts A–C are solid)

- **Tree-of-Thought "thinking mode"** — the top backup elective: *adaptive reasoning depth* mirrors *adaptive retrieval depth*. Thematically on-brand, but generation-side (shares no retrieval machinery) and its gain is hard to show on a local 7B model — so it's additive, not reinforcing. Add as a user-toggled mode only after the retrieval bundle is done.
- **A fine-tuned query-rewriter (QLoRA)** — train a small adapter for `rewrite_query` and show in the ablation that it beats the base model. The one fine-tune that serves the thesis.
- **A larger / different corpus** to show the pipeline generalises beyond Simple-English Wikipedia.

---

## 10. Risk register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Loop fixes change behaviour mid-eval | Inconsistent numbers | Milestone 1 (correctness) fully precedes Milestone 2 (measurement). |
| Benchmark adaptation (HotpotQA → local corpus) is fiddly | Slips Milestone 2 | Start with a small subset; index exactly the gold passages. |
| LLM-judge metrics noisy on a 7B model | Weak eval signal | Use a stronger local judge if available; report variance; spot-check by hand. |
| PDF text extraction quality varies | Garbage chunks from user docs | Validate extraction; skip/flag unparseable PDFs; keep to text PDFs. |
| Web traversal is non-deterministic (live pages, rate limits, failures) | Flaky eval + demo | Eval the routing *decision*, not exact answers; cache fetched pages; robust timeouts/fallbacks. |
| HF free CPU tier too slow for live demo | Broken demo link | Milestone 8 deploy fix; recorded demo as fallback. |
| Scope creep toward a general agent | Dilutes the thesis | §8 is the contract — revisit only via §9 after Parts A–C are done. |

---

## 11. Execution order

**M1 → M2 (with M7 in parallel) → M3 → M4 → M5 → M6 → M8.**

Rationale: correctness first (can't honestly measure a buggy loop); then the eval that *is* the project's value, with tracing (M7) feeding its cost metrics; then the agentic capabilities in **local-before-web** order — user documents (M3), then compression/isolation (M4, which also completes M3's summarization requirement), then the open web (M5, the messy non-deterministic part) last; then robustness/efficiency (M6) quantified by the eval; shipping/docs/demo (M8) to close.

> **Definition of done:** the README states a clear claim and backs it with a reproducible ablation on a named benchmark; Scout retrieves over the user's own documents and the open web, routing correctly between them; the loop is correct, reranked, compressed, cached, and guarded; every query emits a trace the UI shows; CI is green on tests + lint + types; a working or recorded demo exists; limitations are documented honestly.
