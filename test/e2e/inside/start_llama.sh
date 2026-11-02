#!/usr/bin/env bash
# Start llama.cpp's OpenAI-compatible server on 11434.
set -euo pipefail

: "${SALARYMAN_MODEL_PATH:?SALARYMAN_MODEL_PATH is not set}"

if [[ ! -f "$SALARYMAN_MODEL_PATH" ]]; then
  echo "error: model not found: $SALARYMAN_MODEL_PATH" >&2
  exit 1
fi

exec llama-server \
  -m "$SALARYMAN_MODEL_PATH" \
  --host 127.0.0.1 --port 11434 \
  -c 1024 --parallel 1 \
  --no-webui \
  --log-disable
