#!/usr/bin/env bash
# Pull Foundation-Sec-8B-Instruct into Ollama (Path A — local open weights, no Splunk Cloud).
# Official weights: https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Instruct
# Community GGUF (Q8_0 ~8.5 GB): https://huggingface.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF
#
# Usage:
#   bash scripts/sh/setup_foundation_sec_ollama.sh
#   export AGENTSIGHT_OLLAMA_CHAT_MODEL='hf.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF:Q8_0'
#   export AGENTSIGHT_AI_MODEL='hf.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF:Q8_0'

set -euo pipefail

MODEL_TAG="${FOUNDATION_SEC_OLLAMA_TAG:-hf.co/gabriellarson/Foundation-Sec-8B-Instruct-GGUF:Q8_0}"

echo "=== Foundation-Sec via Ollama (Path A) ==="
echo "Model tag: ${MODEL_TAG}"
echo ""

if ! command -v ollama >/dev/null 2>&1; then
  echo "ERROR: ollama not found. Install from https://ollama.com" >&2
  exit 1
fi

echo "Pulling model (first run downloads ~8 GB for Q8_0)..."
ollama pull "${MODEL_TAG}"

echo ""
echo "Smoke test:"
ollama run "${MODEL_TAG}" "Classify in one sentence: 15 identical splunk_run_query MCP calls in 10 minutes."

echo ""
echo "=== Next steps ==="
echo "1. AI Toolkit → Connections → Ollama → base URL http://127.0.0.1:11434"
echo "2. Set classify env (or use apps/agentsight/default/ai.conf):"
echo "   export AGENTSIGHT_AI_MODEL='${MODEL_TAG}'"
echo "   export AGENTSIGHT_AI_PROVIDER='Ollama'"
echo "   export AGENTSIGHT_AI_CONNECTION='ollama_local'"
echo "   # Investigation agent chat stays llama3.2:latest (Foundation-Sec GGUF lacks tool calling)"
echo "   export AGENTSIGHT_AI_PROVIDER='Ollama'"
echo "   export AGENTSIGHT_AI_CONNECTION='ollama_local'"
echo "3. Pre-flight in Splunk Search:"
echo "   | makeresults count=1"
echo "   | eval prompt=\"Classify this MCP agent behavior: agent ran outputlookup via splunk_run_query.\""
echo "   | ai provider=Ollama model=\"${MODEL_TAG}\" connection=ollama_local prompt=\"'\$prompt\$'\""
