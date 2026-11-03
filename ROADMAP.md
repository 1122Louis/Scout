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
4. **Production instincts** — a clean service API, observability, caching, graceful degradation, CI, a working demo.
5. **Honesty** — documented limitations and failure cases, not just the happy path.

---

## 2. Current snapshot & the stack pivot

**Today:** a single-process **Python + marimo** prototype — UI-free core (`rag_core.py`) + marimo UI (`app.py`), DuckDB VSS/HNSW store, Ollama models, pytest + CI. The agentic loop's skeleton (`judge → rewrite → retrieve → judge → generate`) is **already built**, but it has correctness bugs, nothing measures it, and it only reads a fixed Wikipedia corpus.

**Target:** a **three-tier polyglot system** (see §Architecture) — a **React/TypeScript** UI, a **Go** service that owns the agent runtime, and **Python** kept as the *offline* evaluation + fine-tuning sidecar. The existing Python loop becomes the **reference implementation** we prove, measure, and then port to Go.

---

## Architecture (target)

```
┌─────────────────────┐      HTTP / SSE      ┌──────────────────────────────┐
│   React + TS (UI)   │ ◀──────streaming────▶ │        Go service (API)       │
│  chat · streaming · │                       │  agentic loop (route→judge→   │
│  conv view · trace  │                       │  retrieve→summarize→refine) · │
│  · doc upload       │                       │  DuckDB+VSS · Ollama client · │
└─────────────────────┘                       │  PDF ingest · web crawler     │
                                               └──────────────┬───────────────┘
                                                      same DuckDB store + Ollama
                                               ┌──────────────▼───────────────┐
                                               │   Python sidecar (OFFLINE)    │
                                               │  eval harness (HotpotQA,      │
                                               │  faithfulness) hits the Go    │
                                               │  API · QLoRA fine-tuning      │
                                               └───────────────────────────────┘
```

- **React/TS** — chat UI, SSE streaming, conversation view, trace panel, document upload. (Replaces marimo, which gave streaming/chat/progress for free — now hand-built.)
- **Go** — the runtime: agentic loop, DuckDB+VSS vector store (`go-duckdb`), Ollama HTTP client, PDF text extraction, and the concurrent **web crawler** (Go's sweet spot). Single-binary deploy.
- **Python** — **offline only**: the eval harness (hits the Go API end-to-end — tests the real service) and optional QLoRA training. Never in the request path, so no Go↔Python runtime bridge.

**Decision (change only if you overrule it):** Python stays as the offline eval/training sidecar — reimplementing RAGAS/HotpotQA tooling in Go would weaken the headline for no gain.

---

## 3. Guiding principles

1. **Measure the thesis.** "Adaptive" is a hypothesis until an ablation proves it. Numbers go in the README.
2. **Correct before measured; measured before ported.** Fix the loop and prove it **in Python first** (cheap, already tested) — never gamble the headline on finishing the Go/React rewrite.
3. **Depth over breadth.** Every addition must strengthen the *retrieval* thesis or it doesn't ship (§8 is the contract).
4. **Local & correct before live & messy.** User-documents and eval come before web traversal.
5. **Clean service boundary.** The Go service owns all retrieval/agent logic behind an HTTP/SSE API; React only renders and streams; the Python sidecar hits the same API offline.
6. **Reproducible by a stranger.** Pinned seeds/versions, one-command eval, documented models/hardware.

---

## PART A — Foundation (prove it in Python first)

### Milestone 1 — Make the engine *correct*

Fix the agentic loop's real bugs in the current Python code — this is the reference implementation we later port to Go.

- [ ] **Accumulate evidence across refine rounds.** `app.py` resets `docs = []` each round, discarding earlier good hits. Accumulate + dedupe across rounds.
- [ ] **Global rerank before truncation.** Merge all hits across the N sub-queries, sort by cosine distance globally, *then* take top-K.
- [ ] **Structured LLM outputs.** Replace the regex `_extract_json` with Ollama's `format=`/JSON-schema constrained decoding; keep fallbacks as a backstop.
- [ ] **Integration test of the loop** (fake retriever + fake LLM): routing short-circuits, refine accumulates, loop always terminates.

**Acceptance:** the refine loop grows its evidence set across rounds; final context is the globally-top-K; an integration test locks the control flow.

### Milestone 2 — Prove it works *(the headline)*

Measure the thesis on **recognized benchmarks** and publish the ablation — all in Python, before the port.

- [ ] **Benchmarks:** a **HotpotQA** subset (multi-hop → justifies the refine loop) + a routing-stress set (factual Qs mixed with chit-chat/math → tests `judge_query`).
- [ ] **Retrieval metrics:** recall@k, MRR, nDCG. **Answer metrics:** faithfulness/groundedness + answer-relevance. **Cost metrics:** LLM calls, tokens, latency.
- [ ] **The ablation:** `no-RAG` vs `naive always-retrieve` vs `adaptive-routing` vs `adaptive + refine loop` — quality **and** cost.
- [ ] **Error analysis:** 3–5 failure cases. **Reproducible:** `uv run python -m eval` → the table. Publish it in the README; backfill the CV bullets.

**Acceptance:** a reproducible command produces an ablation on a named benchmark showing adaptive routing cutting LLM calls at equal quality, and the refine loop improving groundedness on multi-hop questions.

---

## PART B — Stack swap + agentic capabilities

### Milestone 3 — Stack swap: Go service + React UI

Port the *proven, measured* loop to the target architecture.

- [ ] **Spike first:** confirm DuckDB **VSS/HNSW loads and queries from `go-duckdb`**. If not, keep the vector store as a thin Python service behind the Go API and record the decision here.
- [ ] **Go service** exposing an HTTP/SSE API: port `judge → rewrite → retrieve → summarize → refine → generate`, DuckDB+VSS access, and the Ollama client. Unit-test the ported logic against the Python reference's expectations.
- [ ] **React/TS UI:** chat with **SSE streaming**, visible + scrollable history, and the live reasoning/trace stream (the feature marimo gave for free).
- [ ] **Point the Python eval harness at the Go API** so Milestone 2's ablation now measures the *real* service end-to-end.

**Acceptance:** the React UI streams answers from the Go service; the Go loop reproduces the Python reference's behaviour; the eval harness runs against the Go API and matches (within tolerance) the pre-port numbers.

### Milestone 4 — User-provided documents *(elective)*

- [ ] **`.txt`/`.pdf` ingestion** in the Go service — PDF via text extraction (**text only — no OCR/images**, which would cross into the multimodal elective).
- [ ] **Upload in the React UI**; build/extend the DuckDB store, reusing the chunk → embed → HNSW path. Idempotent re-ingest. Each chunk carries source provenance for citations.

**Acceptance:** a user uploads a PDF + a text file, Scout indexes them, and answers grounded in them with correct source citations; re-ingesting is a no-op.

### Milestone 5 — Context management: summarization + isolation *(electives, two-for-one)*

- [ ] **Compression / summarization** of retrieved chunks before generation (this *is* the summarization the adaptive-RAG elective requires). Measure token reduction + faithfulness impact in the eval.
- [ ] **Context isolation** — each sub-query's context kept separate during the refine loop, merged only at generation.

**Acceptance:** compression cuts context tokens by a measurable % at equal-or-better faithfulness (shown in eval); isolation prevents cross-contamination between sub-queries.

### Milestone 6 — Agentic web retrieval *(elective — Go's sweet spot)*

- [ ] **Concurrent web retriever in Go:** search *and* fetch-and-read real pages (traverse to the page, extract content — beyond snippets), with timeouts, rate limits, polite crawling, and graceful fallback.
- [ ] **Routing generalises:** router decides **direct / local-corpus / web**; `judge_retrieved` can **escalate local → web** when local context is insufficient.
- [ ] **Eval the decision, not the answer:** measure routing accuracy (did it choose web when local lacked the answer?), since live web answers are non-deterministic.

**Acceptance:** a question unanswerable locally triggers a web search that fetches and reads a real page and grounds the answer with the source URL; routing accuracy is measured.

---

## PART C — Hardening & shipping

### Milestone 7 — Robustness & efficiency
- [ ] **Reranking** (cross-encoder or MMR) on top of cosine retrieval; reflected in eval numbers.
- [ ] **Caching** of query embeddings / retrieval results; measure the win.
- [ ] **Guardrails** — honest "not in context" on weak retrieval instead of hallucinating.
- [ ] **Config** — one source of truth across the Go service (kill the `N_ARTICLES` drift and magic numbers).
- [ ] **Graceful degradation** when Ollama / a model / the web is unavailable.

### Milestone 8 — Observability
- [ ] **Per-request trace** (stage, latency, tokens, routing decision direct/local/web, # refine rounds) emitted by the Go service.
- [ ] **Structured logging** (JSON lines) the eval harness aggregates for cost metrics.
- [ ] **React trace panel** showing *why* each query was routed/refined/escalated — makes the adaptive behaviour the centrepiece of the demo.

### Milestone 9 — Shippable & legible
- [ ] **CI across all three tiers:** Go (`go vet`, `golangci-lint`, `go test`), TS (typecheck + lint), Python (pytest + ruff + mypy).
- [ ] **Packaging:** Go single-binary that serves the built React static assets; one-command run.
- [ ] **Deploy:** containerise the Go binary + Ollama; fix the `rag.duckdb` store shipping (the current Dockerfile claims Git LFS but the file is gitignored with no LFS). **Verify the demo link boots** (or ship a recorded demo).
- [ ] **README front door:** problem → claim → ablation table → architecture diagram → reproduce → **documented limitations** + ADR-style design notes (why Go runtime, why Python eval, why routing-before-retrieval).
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
| Concurrent multi-user | Backend/infra, not thesis. |
| Advanced prompt caching (H2O) | KV-cache eviction *inside the inference engine* — impossible on Ollama's HTTP API. |

## 9. Optional stretch (only once Parts A–C are solid)

- **Tree-of-Thought "thinking mode"** — top backup elective: *adaptive reasoning depth* mirrors *adaptive retrieval depth*, but it's generation-side (shares no retrieval machinery) and hard to show on a local 7B model.
- **Fine-tuned query-rewriter (QLoRA)** — the one fine-tune that serves the thesis; show it beats the base model in the ablation.
- **Larger / different corpus** to show generalisation beyond Simple-English Wikipedia.

---

## 10. Risk register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Stack swap balloons scope and the project ships half-done | A polished Python app beats an unfinished rewrite | **Prove in Python (M1–M2) before porting (M3);** frontend can scaffold in parallel. |
| DuckDB VSS/HNSW not usable from `go-duckdb` | Blocks the Go vector store | Spike it first (M3); fall back to a thin Python vector service behind the Go API. |
| Rebuilding chat/streaming marimo gave for free | Slips M3 | Use a mature TS AI/streaming lib; keep the first UI minimal. |
| Polyglot CI/integration complexity | Slows every milestone | Clean HTTP/SSE contract; test each tier independently; one compose file. |
| Loop fixes change behaviour mid-eval | Inconsistent numbers | M1 precedes M2. |
| Web traversal non-deterministic (live pages, rate limits) | Flaky eval + demo | Eval the routing *decision*; cache fetched pages; robust timeouts/fallbacks. |
| HF free CPU tier too slow for live demo | Broken demo link | M9 deploy fix; recorded demo as fallback. |
| Scope creep toward a general agent | Dilutes the thesis | §8 is the contract. |

---

## 11. Execution order

**M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9**, with the **React scaffolding allowed to start in parallel with M2**.

Rationale: prove the thesis in the cheap, already-tested Python loop (M1–M2) so the headline numbers are locked in; *then* do the impressive three-tier port (M3); then the agentic capabilities in local-before-web order (M4 docs → M5 compression → M6 web, Go's strength, last because it's the messy non-deterministic part); then hardening (M7), observability (M8, which also powers the demo), and shipping (M9).

> **Definition of done:** a reproducible ablation on a named benchmark backs a clear claim; Scout runs as a React UI over a Go service, retrieving across the user's documents and the open web and routing correctly between them; the loop is correct, reranked, compressed, cached, guarded; every query emits a trace the UI shows; CI is green across Go + TS + Python; a working or recorded demo exists; limitations are documented.
