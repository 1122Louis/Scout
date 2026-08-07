---
title: Adaptive RAG
emoji: 🔎
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
license: mit
---

# Adaptive RAG — Live Demo

A chat app that decides *how much* retrieval each query needs — routing simple
questions straight to the model, and running a retrieve → judge → rewrite loop
for the ones that need grounding.

This hosted demo runs a smaller open model (`qwen2.5:3b`) to fit the free CPU
tier. Retrieval is unchanged from the full project (neural IR over a DuckDB +
HNSW store, `nomic-embed-text` embeddings).

▶️ **Source & full writeup:** https://github.com/1122Louis/Adaptive-RAG-Project

Try:
- *"Hello, how are you?"* → answered directly (no retrieval).
- *"What is the history of the Eiffel Tower?"* → full retrieve → judge → generate loop with citations.
