# Scout — Engineering Roadmap

> **The thesis.** Most RAG systems retrieve for *every* query, blindly. **Scout is an adaptive retrieval agent (agentic RAG)**: it decides *whether* to retrieve, *what* to search for, *where* to look — the user's own documents or the open web — and *how much* to retrieve, judging its own results and looping to refine, then **compressing what it finds to fit the budget** — and it **proves, with numbers, that this saves cost without sacrificing answer quality.**
>
> It is an **agent whose job is retrieval** — not a general-purpose agent. Features that would make retrieval just one tool among many (arbitrary tool-calling, code execution, sub-agents) are out of scope (§8).
>
> This is a living document: check items off as PRs land. "Done" = the acceptance criteria are demonstrably true.

---

## 1. What "solid" means here

A reviewer (recruiter, staff engineer, researcher) should be able to open the repo and, in five minutes, see:

1. **A clear problem and a clear claim** — stated in the README's first paragraph.
2. **Evidence the claim is true** — an ablation table with real numbers on a recognized benchmark.
3. **Correct, readable engineering** — a tested core, typed, with the agentic loop actually doing what it says.
4. **Production instincts** — a clean API, observability, caching, graceful degradation, CI, a working demo.
5. **Honesty** — documented limitations and failure cases, not just the happy path.

---

## 2. Current snapshot

**Today:** a single-process **Python + marimo** prototype — UI-free core (`rag_core.py`) + marimo UI (`app.py`), DuckDB VSS/HNSW store, Ollama models, pytest + CI. The agentic loop's skeleton (`judge → rewrite → retrieve → judge → generate`) is **already built**, but it has correctness bugs, nothing measures it, and it only reads a fixed Wikipedia corpus.

**Target:** keep **all logic and ML in Python** (so fine-tuning stays first-class), expose it through a **FastAPI** service, and put a polished **Next.js + TypeScript** web UI on top. TypeScript lives only where it belongs — the browser. The marimo UI is the one piece replaced.

---

## Architecture (target)

```
┌──────────────────────────┐   HTTP / SSE   ┌───────────────────────────────┐
│  Next.js + TypeScript     │ ◀───stream────▶ │  FastAPI  (Python)            │
│  chat · streaming · conv  │                 │  thin API over the core       │
│  view · doc upload · trace│                 └───────────────┬───────────────┘
└──────────────────────────┘                                 │ imports
                                              ┌───────────────▼───────────────┐
                                              │  Python core (UI-free)         │
                                              │  agentic loop (route→judge→    │
                                              │  retrieve→summarize→refine) ·  │
                                              │  DuckDB+VSS · Ollama · PDF      │
                                              │  ingest · async web crawler    │
                                              ├────────────────────────────────┤
                                              │  Offline: eval harness (Hotpot │
                                              │  QA, faithfulness) · QLoRA      │
                                              │  fine-tuning                    │
                                              └────────────────────────────────┘
```

- **Python core** — all retrieval/agent logic, the DuckDB+VSS vector store, Ollama calls, PDF ingestion, the async web crawler, **plus** the offline eval harness and (later) QLoRA fine-tuning. This is where the project's value and your ML signal live.
- **FastAPI** — a thin HTTP/SSE layer that streams the core's output; it holds no business logic.
- **Next.js + TypeScript** — the product UI: chat with streaming, conversation view, document upload, trace panel. The TS is justified — it's the browser, the right place for a second language (unlike a backend rewrite).
- **Gradio (optional, early)** — a few-line Python chat UI used only to get a free one-click Hugging Face Spaces demo *before* the Next.js app exists, so there's a working live link early.

---

## 3. Guiding principles

1. **Measure the thesis.** "Adaptive" is a hypothesis until an ablation proves it. Numbers go in the README.
2. **Prove it before you dress it up.** Fix the loop and run the eval **in plain Python first** — never gamble the headline on finishing the web app.
3. **Depth over breadth.** Every addition must strengthen the *retrieval* thesis or it doesn't ship (§8 is the contract).
4. **Local & correct before live & messy.** User-documents and eval come before web traversal.
5. **One source of truth.** All logic in the Python core; FastAPI is a thin wrapper; Next.js only renders and streams.
6. **Reproducible by a stranger.** Pinned seeds/versions, one-command eval, documented models/hardware.

---

## PART A — Foundation (prove it in Python)

### Milestone 1 — Make the engine *correct*

Fix the agentic loop's real bugs in the Python core.

- [ ] **Accumulate evidence across refine rounds.** `app.py` resets `docs = []` each round, discarding earlier good hits. Accumulate + dedupe across rounds.
- [ ] **Global rerank before truncation.** Merge all hits across the N sub-queries, sort by cosine distance globally, *then* take top-K.
- [ ] **Structured LLM outputs.** Replace the regex `_extract_json` with Ollama's `format=`/JSON-schema constrained decoding; keep fallbacks as a backstop.
- [ ] **Integration test of the loop** (fake retriever + fake LLM): routing short-circuits, refine accumulates, loop always terminates.

**Acceptance:** the refine loop grows its evidence set across rounds; final context is the globally-top-K; an integration test locks the control flow.

### Milestone 2 — Prove it works *(the headline)*

Measure the thesis on **recognized benchmarks** and publish the ablation — plain Python, before the web app.

- [ ] **Benchmarks:** a **HotpotQA** subset (multi-hop → justifies the refine loop) + a routing-stress set (factual Qs mixed with chit-chat/math → tests `judge_query`).
- [ ] **Retrieval metrics:** recall@k, MRR, nDCG. **Answer metrics:** faithfulness/groundedness + answer-relevance. **Cost metrics:** LLM calls, tokens, latency.
- [ ] **The ablation:** `no-RAG` vs `naive always-retrieve` vs `adaptive-routing` vs `adaptive + refine loop` — quality **and** cost.
- [ ] **Error analysis:** 3–5 failure cases. **Reproducible:** `uv run python -m eval` → the table. Publish it in the README; backfill the CV bullets.
- [ ] *(Optional)* **Gradio demo** — a few-line `gr.ChatInterface` deployed to Hugging Face Spaces for an early working live link while the Next.js app is built later.

**Acceptance:** a reproducible command produces an ablation on a named benchmark showing adaptive routing cutting LLM calls at equal quality, and the refine loop improving groundedness on multi-hop questions.

---

## PART B — Web app + agentic capabilities

### Milestone 3 — Serve it: FastAPI + Next.js web app

Put the proven core behind an API and a real UI.

- [ ] **FastAPI service** wrapping the Python core: endpoints for chat (with **SSE token streaming**), document upload, and conversation state. No business logic in the API layer — it only calls the core.
- [ ] **Next.js + TypeScript frontend:** chat with streaming (consume SSE), visible + scrollable history, and a live reasoning/trace stream (the feature marimo gave for free).
- [ ] **Retire the marimo UI** (`app.py`); the Python core (`rag_core.py`) is untouched by the swap.
- [ ] **Local dev:** one command (e.g. a compose file / Makefile) brings up API + frontend + Ollama.

**Acceptance:** the Next.js UI streams answers from the FastAPI service end-to-end; the Python core is unchanged; the eval harness still runs directly against the core.

### Milestone 4 — User-provided documents *(elective)*

- [ ] **`.txt`/`.pdf` ingestion** in the Python core — PDF via text extraction (`pypdf`-style; **text only — no OCR/images**, which would cross into the multimodal elective).
- [ ] **Upload in the Next.js UI** → FastAPI → core builds/extends the DuckDB store, reusing chunk → embed → HNSW. Idempotent re-ingest; each chunk carries source provenance for citations.

**Acceptance:** a user uploads a PDF + a text file, Scout indexes them, and answers grounded in them with correct source citations; re-ingesting is a no-op.

### Milestone 5 — Context management: summarization + isolation *(electives, two-for-one)*

- [ ] **Compression / summarization** of retrieved chunks before generation (this *is* the summarization the adaptive-RAG elective requires). Measure token reduction + faithfulness impact in the eval.
- [ ] **Context isolation** — each sub-query's context kept separate during the refine loop, merged only at generation.

**Acceptance:** compression cuts context tokens by a measurable % at equal-or-better faithfulness (shown in eval); isolation prevents cross-contamination between sub-queries.

### Milestone 6 — Agentic web retrieval *(elective)*

- [ ] **Async web retriever in Python** (e.g. `httpx` + a content extractor like `trafilatura`): search *and* fetch-and-read real pages (traverse to the page, extract content — beyond snippets), with timeouts, rate limits, polite crawling, and graceful fallback.
- [ ] **Routing generalises:** router decides **direct / local-corpus / web**; `judge_retrieved` can **escalate local → web** when local context is insufficient.
- [ ] **Eval the decision, not the answer:** measure routing accuracy (did it choose web when local lacked the answer?), since live web answers are non-deterministic.

**Acceptance:** a question unanswerable locally triggers a web search that fetches and reads a real page and grounds the answer with the source URL; routing accuracy is measured.

---

## PART C — Hardening & shipping

### Milestone 7 — Robustness & efficiency
- [ ] **Reranking** (cross-encoder or MMR) on top of cosine retrieval; reflected in eval numbers.
- [ ] **Caching** of query embeddings / retrieval results; measure the win.
- [ ] **Guardrails** — honest "not in context" on weak retrieval instead of hallucinating.
- [ ] **Config** — one source of truth in the core (kill the `N_ARTICLES` drift and magic numbers).
- [ ] **Graceful degradation** when Ollama / a model / the web is unavailable.

### Milestone 8 — Observability
- [ ] **Per-request trace** (stage, latency, tokens, routing decision direct/local/web, # refine rounds) produced by the core, exposed via the API.
- [ ] **Structured logging** (JSON lines) the eval harness aggregates for cost metrics.
- [ ] **Next.js trace panel** showing *why* each query was routed/refined/escalated — the centrepiece of the demo.

### Milestone 9 — Shippable & legible
- [ ] **CI across both tiers:** Python (pytest + ruff + mypy) and TypeScript (typecheck + lint + build).
- [ ] **Deploy:** Next.js on Vercel; FastAPI + Ollama in a container (Render/Fly/HF Docker). **Verify the demo link boots** — and since hosting Ollama live on a free tier is the hard part, the Gradio HF Spaces demo and/or a recorded video are acceptable fallbacks for the live link.
- [ ] **README front door:** problem → claim → ablation table → architecture diagram → reproduce → **documented limitations** + ADR-style notes (why Python core + FastAPI + Next.js, why routing-before-retrieval).
- [ ] **Demo:** a GIF/video — simple query skips retrieval; hard query triggers the refine loop; out-of-corpus query escalates to the web — trace visible throughout.

---

## 8. Out of scope — and *why* (deliberate cuts)

These would make retrieval just one tool among many, turning Scout from focused **agentic RAG** into an unfocused general agent:

| Cut elective | Why |
|--------------|-----|
| Extensible user tool-calling | Generic agent feature; user *shell* tools drag in the code-sandbox burden. |
| Sub-agent deployment (async) | Orchestration axis orthogonal to retrieval. |
| Secure code execution / sandbox | A separate systems project; retrieval not involved. |
| Preference optimization (DPO/RLHF) | A separate generation-side training pipeline. |
| Multimodal ingestion (VLM) | Different model stack; PDF-as-*text* (M4) stays on the right side of this line. |
| Concurrent multi-user | Backend/infra, not thesis (FastAPI makes it possible later, but it's not a goal). |
| Advanced prompt caching (H2O) | KV-cache eviction *inside the inference engine* — impossible on Ollama's HTTP API. |

## 9. Optional stretch (only once Parts A–C are solid)

- **Fine-tuned query-rewriter (QLoRA)** — the one fine-tune that serves the thesis. Train a small adapter for `rewrite_query` (PEFT/unsloth/TRL — all Python, which is exactly why the core stays Python), serve it via Ollama, and show in the ablation that it beats the base model. The Python-only stack keeps this door fully open.
- **Tree-of-Thought "thinking mode"** — top backup elective: *adaptive reasoning depth* mirrors *adaptive retrieval depth*, but it's generation-side and hard to show on a local 7B model.
- **Larger / different corpus** to show generalisation beyond Simple-English Wikipedia.

---

## 10. Risk register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Building the Next.js app balloons scope and the project ships half-done | A polished Python+Gradio app beats an unfinished Next.js one | **Prove in Python (M1–M2)** and ship the optional Gradio demo *before* the Next.js build; it's the fallback live link. |
| Rebuilding chat/streaming that marimo/Gradio give for free | Slips M3 | Keep the first Next.js UI minimal; use a mature SSE/chat pattern. |
| Two-service deploy (Vercel + API+Ollama host) ops | Slows M9 | One compose file for local; Gradio/HF + recorded demo as the live-link fallback. |
| TypeScript is a second language | Split focus | It's frontend-only and the right tool there; the ML/core stays 100% Python. |
| Loop fixes change behaviour mid-eval | Inconsistent numbers | M1 precedes M2. |
| Web traversal non-deterministic (live pages, rate limits) | Flaky eval + demo | Eval the routing *decision*; cache fetched pages; robust timeouts/fallbacks. |
| Hosting Ollama live on a free tier | Broken live demo | Gradio HF Spaces demo + recorded video as fallbacks (M9). |
| Scope creep toward a general agent | Dilutes the thesis | §8 is the contract. |

---

## 11. Execution order

**M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9**, with the optional **Gradio demo shipped at M2** and the **Next.js scaffolding allowed to start in parallel with M3's API**.

Rationale: prove the thesis in the cheap, already-tested Python loop (M1–M2) and get an early live demo via Gradio; *then* build the FastAPI + Next.js web app (M3); then the agentic capabilities in local-before-web order (M4 docs → M5 compression → M6 web, last because it's the messy non-deterministic part); then hardening (M7), observability (M8, which also powers the demo), and shipping (M9).

> **Definition of done:** a reproducible ablation on a named benchmark backs a clear claim; Scout runs as a Next.js UI over a FastAPI service wrapping an all-Python core, retrieving across the user's documents and the open web and routing correctly between them; the loop is correct, reranked, compressed, cached, guarded; every query emits a trace the UI shows; CI is green across Python + TypeScript; a working or recorded demo exists; limitations are documented; the Python core keeps the door open to QLoRA fine-tuning.
