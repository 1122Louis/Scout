# Hugging Face Spaces (Docker SDK) image for the Adaptive RAG demo.
# Runs Ollama + a smaller open model (qwen2.5:3b) so it fits the free CPU tier,
# while keeping retrieval identical (nomic-embed-text + the prebuilt DuckDB store).
FROM python:3.12-slim

# System deps + Ollama
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://ollama.com/install.sh | sh

# HF Spaces runs the container as uid 1000
RUN useradd -m -u 1000 user
USER user

ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    OLLAMA_HOST=127.0.0.1:11434 \
    OLLAMA_MODELS=/home/user/.ollama/models \
    RAG_CHAT_MODEL=qwen2.5:3b-instruct \
    RAG_EMBED_MODEL=nomic-embed-text \
    RAG_EMBED_DIM=768 \
    RAG_DB_PATH=/home/user/app/rag.duckdb

WORKDIR /home/user/app

# Python deps (installed into the user site so PATH picks up the marimo console script)
COPY --chown=user requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Pre-cache the DuckDB VSS extension so the app doesn't fetch it at runtime
RUN python -c "import duckdb; c = duckdb.connect(); c.execute('INSTALL vss;'); c.close()"

# Bake the Ollama models into the image -> instant cold starts (no re-pull on wake)
RUN ollama serve > /tmp/ollama.log 2>&1 & \
    for i in $(seq 1 30); do curl -sf http://127.0.0.1:11434/ >/dev/null 2>&1 && break; sleep 1; done; \
    ollama pull qwen2.5:3b-instruct && \
    ollama pull nomic-embed-text

# App code + prebuilt vector store (rag.duckdb ships via Git LFS)
COPY --chown=user . .

EXPOSE 7860
CMD ["bash", "start.sh"]
