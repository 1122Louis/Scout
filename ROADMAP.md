# Adaptive RAG — Engineering Roadmap

> **The thesis.** Most RAG systems retrieve for *every* query, blindly. This one **decides how much retrieval each query needs** — routing simple queries straight to the model, and running an iterative *retrieve → self-critique → refine* loop only when grounding is required — and **proves, with numbers, that this saves cost without sacrificing answer quality.**
>
> A solid project is **deep on one claim**, not broad on many features. Everything in this roadmap serves that single thesis. Generic chat-app features that don't (multi-conversation UIs, model-switching, fine-tuning) are explicitly out of scope (§8) — cut on purpose, not forgotten.
>
> This is a living document: check items off as PRs land. "Done" = the acceptance criteria are demonstrably true.

---

## 1. What "solid" means here

A reviewer (recruiter, staff engineer, researcher) should be able to open the repo and, in five minutes, see:

1. **A clear problem and a clear claim** — stated in the README's first paragraph.
2. **Evidence the claim is true** — an ablation table with real numbers on a recognized benchmark.
3. **Correct, readable engineering** — a tested core, typed, linted, with the adaptive loop actually doing what it says.
4. **Production instincts** — observability, caching, graceful degradation, CI, a working demo.
5. **Honesty** — documented limitations and failure cases, not just the happy path.

If any of these five is missing, the project is a demo, not a portfolio piece.

---

## 2. Current snapshot

**Solid foundation already in place:**
- UI-free, testable core (`rag_core.py`) cleanly separated from the marimo UI (`app.py`).
- Adaptive pipeline (`judge_query → rewrite_query → retrieve → judge_retrieved → generate`) with JSON fallbacks.
- DuckDB VSS/HNSW vector store, sentence-aware chunking, batched Ollama embeddings.
- Runnable via `uv`; unit tests for parsing/fallbacks; CI (pytest); Dockerfile + HF Spaces scaffold.

**The gap in one sentence:** the system *claims* to be adaptive and self-critiquing, but **nothing measures whether any of it helps**, and the loop has correctness bugs that undercut the claim. That is what this roadmap fixes.

---

## 3. Guiding principles

1. **Measure the thesis.** "Adaptive" is a hypothesis until an ablation proves it. Numbers go in the README.
2. **Correct before measured.** Fix the loop bugs first — never publish numbers for a system that's doing the wrong thing.
3. **Depth over breadth.** Every addition must strengthen the core claim or it doesn't ship.
4. **Keep the core UI-free and testable.** New capability lands in importable modules; the UI only orchestrates.
5. **Reproducible by a stranger.** Pinned seeds, one-command eval, documented models/hardware.

---

## Milestone 1 — Make the engine *correct*

The adaptive loop has real bugs that must be fixed before any honest measurement.

- [ ] **Accumulate evidence across refine rounds.** `app.py` resets `docs = []` each round, discarding earlier good hits — so the refine loop *loses* context instead of adding to it. Accumulate + dedupe across rounds.
- [ ] **Global rerank before truncation.** Merge all hits across the N sub-queries, sort by cosine distance globally, *then* take top-K. Today it feeds the first-K-after-dedup, which may not be the best-K.
- [ ] **Structured LLM outputs.** Replace the regex `_extract_json` with Ollama's `format=`/JSON-schema constrained decoding for `judge_query`, `rewrite_query`, `judge_retrieved`. Keep the existing fallbacks as a backstop.
- [ ] **Integration test of the loop** with a fake retriever + fake LLM, asserting: routing short-circuits correctly, refine accumulates docs, loop always terminates.

**Acceptance:** the refine loop demonstrably grows its evidence set across rounds; the final context is the globally-top-K by similarity; an integration test locks the control flow; JSON parsing no longer depends on a regex.

---

## Milestone 2 — Prove it works *(the headline)*

This is what turns a demo into a portfolio piece. Measure the thesis on **recognized benchmarks** and publish the result.

- [ ] **Choose benchmarks that stress the two claims:**
  - **Multi-hop (justifies the refine loop):** a subset of **HotpotQA** — questions that genuinely need iterative retrieval.
  - **Routing (justifies `judge_query`):** a mix of answerable factual questions + non-retrieval queries (chit-chat / math / reasoning) so routing has something to get right or wrong.
- [ ] **Retrieval metrics:** recall@k, MRR, nDCG against gold supporting passages.
- [ ] **Answer metrics:** faithfulness/groundedness + answer-relevance (RAGAS-style or a local LLM-judge — the machinery already exists).
- [ ] **Cost metrics:** LLM calls, tokens, and wall-clock latency per query (data comes from Milestone 4's tracing).
- [ ] **The ablation** (the money table): `no-RAG` vs `naive always-retrieve` vs `adaptive-routing` vs `adaptive + refine loop`. Report quality **and** cost for each.
- [ ] **Error analysis:** a short section with 3–5 concrete failure cases and what they reveal (routing misfires, retrieval misses, judge false-positives). Seniors show where it breaks.
- [ ] **One-command, seeded, reproducible eval:** `uv run python -m eval` → the table.
- [ ] **Publish the ablation table in the README** and backfill the real numbers into the CV bullets.

**Acceptance:** a reproducible command produces an ablation table on a named benchmark showing adaptive routing cutting LLM calls on simple queries at equal answer quality, and the refine loop improving groundedness on multi-hop questions — with failure cases documented.

---

## Milestone 3 — Make it *robust & efficient*

Production instincts around the proven core.

- [ ] **Reranking:** a cross-encoder reranker (or MMR for diversity) on top of cosine retrieval — the standard next step after bi-encoder retrieval, and it should move the Milestone 2 numbers.
- [ ] **Caching:** cache query embeddings and (optionally) retrieval results — cuts latency and makes the demo snappy. Measure the hit-rate.
- [ ] **Guardrails:** explicit "I don't know / not in the provided context" behaviour when retrieval is weak (distance threshold), rather than hallucinating.
- [ ] **Config consolidation:** one `Config` dataclass/module — kill the `N_ARTICLES` drift (`rag_core.py`=2000 vs `app.py`=1000) and scattered magic numbers.
- [ ] **Graceful degradation:** clear behaviour when Ollama is down or a model is missing (already partially handled — make it deliberate and tested).

**Acceptance:** reranking is in the pipeline and reflected in eval numbers; a cold vs warm query shows measurable cache benefit; weak-retrieval queries get an honest "not found" instead of a hallucination.

---

## Milestone 4 — Make it *observable*

You also need this data to compute Milestone 2's cost metrics, so it pairs naturally.

- [ ] **Per-request trace object:** stage, latency, token counts, routing decision, # refine rounds, chunks retrieved — captured for every query.
- [ ] **Structured logging** of traces (JSON lines) that the eval harness can aggregate.
- [ ] **Surface it in the UI:** the marimo app already streams reasoning steps — extend that to show the trace (which decision, how many rounds, latency per stage). This makes the "adaptive" behaviour *visible* in the demo, which is half the pitch.

**Acceptance:** every query produces a structured trace; the UI visibly shows *why* a query was routed/refined; the eval harness reads traces for its cost column.

---

## Milestone 5 — Make it *shippable & legible*

The finishing layer that signals rigor.

- [ ] **CI rigor:** add `ruff` (lint) + `mypy` (types) + coverage to the existing pytest workflow.
- [ ] **Packaging / entry point:** a clean console entry (`uvx`-installable or `uv run adaptive-rag`) so a stranger runs it in one command.
- [ ] **Fix the live demo:** the Dockerfile claims `rag.duckdb` ships via Git LFS, but it's gitignored and no LFS is configured — so the HF Spaces free CPU tier would try to download + embed on boot and time out. Commit the store via real Git LFS, bake it at build, or prebuild in the Dockerfile. **Verify the link actually boots** (or ship a recorded demo if the tier can't sustain it).
- [ ] **README as the front door:** problem → claim → the ablation table → architecture diagram (extend the existing mermaid) → how to reproduce → **documented limitations**. Add short ADR-style notes on the key design decisions (why DuckDB, why routing-before-retrieval, why local).
- [ ] **Demo artifact:** a GIF/short video showing a simple query skip retrieval and a hard query trigger the refine loop, with the live trace visible.
- [ ] **Professional polish:** remove placeholder/jokey naming (e.g. "MachoChat" → "Adaptive RAG").

**Acceptance:** CI green on tests + lint + types; one-command run for a stranger; a working (or recorded) demo link; a README that states the claim, proves it, and admits its limits.

---

## 8. Out of scope — and *why* (deliberate cuts)

These were on the old, assignment-driven roadmap. Removing the assignment, they add surface area without deepening the thesis, so they are **cut on purpose**:

| Cut feature | Why it doesn't serve a *focused* project |
|-------------|------------------------------------------|
| Multi-conversation management (create/switch/delete/resume) | Generic chat-app plumbing; makes it "another ChatGPT clone," not an adaptive-RAG showcase. |
| Cross-chat "project folder" memory | A whole second retrieval problem that dilutes the single-corpus thesis. |
| Model-switching UI | Switching models for a *user* is a feature; switching them for *eval comparison* (Milestone 2) is the useful version — do that instead. |
| Two fine-tuned LoRA/QLoRA adapters | Large ML lift mostly orthogonal to the thesis. **One** exception worth considering as an optional stretch (§9). |

## 9. Optional stretch (only if the core is done and polished)

- **A fine-tuned query-rewriter (QLoRA).** This is the *one* fine-tune that directly serves the thesis: train a small adapter to produce better diverse retrieval queries, then show in the ablation that it beats the base model's `rewrite_query`. Ollama loads LoRA adapters via a `Modelfile` `ADAPTER` directive, so it fits the existing stack. Do this only after Milestones 1–5 are solid.
- **A larger / different corpus** to show the pipeline generalises beyond Simple-English Wikipedia.

---

## 10. Risk register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Benchmark adaptation (HotpotQA → local corpus) is fiddly | Slips Milestone 2 | Start with a small, well-defined subset; index exactly the gold passages so retrieval metrics are meaningful. |
| LLM-judge metrics are noisy on a 7B model | Weak eval signal | Use a stronger judge model locally if available; report variance; cross-check a sample by hand. |
| Loop fixes change behaviour mid-eval | Inconsistent numbers | Milestone 1 (correctness) fully precedes Milestone 2 (measurement). |
| HF free CPU tier too slow for live demo | Broken demo link | Milestone 5 deploy fix; recorded demo as fallback. |
| Scope creep back toward chat-app features | Dilutes the thesis | §8 is the contract — revisit only via §9 after the core is done. |

---

## 11. Execution order

**Milestone 1 → 2 → 3 → 4 → 5**, with **4 started alongside 2** (tracing feeds the eval cost metrics).

Rationale: correctness first (you can't honestly measure a buggy loop); then the eval that *is* the project's value; then robustness/efficiency improvements that the eval can quantify; observability woven in to power both the metrics and the demo; shipping/docs last.

> **Definition of done:** the README states a clear claim and backs it with a reproducible ablation on a named benchmark; the adaptive loop is correct, reranked, cached, and guarded; every query emits a trace the UI shows; CI is green on tests + lint + types; a working or recorded demo exists; limitations are documented honestly.
