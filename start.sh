#!/usr/bin/env bash
# Entrypoint for the Hugging Face Space: start Ollama, then serve the marimo app.
set -e

# Start Ollama in the background
ollama serve > /tmp/ollama.log 2>&1 &

# Wait for Ollama to accept connections
echo "Waiting for Ollama to start..."
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:11434/ >/dev/null 2>&1; then
    echo "Ollama is up."
    break
  fi
  sleep 1
done

# Serve the app in read-only run mode on the port HF Spaces expects.
exec marimo run app.py --host 0.0.0.0 --port 7860 --no-token
