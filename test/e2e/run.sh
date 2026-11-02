#!/usr/bin/env bash
# Build the image and run the e2e suite.
# Usage: ./run.sh /path/to/models [extra docker run args...]
set -euo pipefail

DOCKER_COMMAND="${DOCKER_COMMAND:-podman}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="${1:?usage: $0 <models-dir>   (must contain model.gguf)}"
shift || true

if [[ ! -f "${MODELS_DIR}/model.gguf" ]]; then
  echo "error: ${MODELS_DIR}/model.gguf not found" >&2
  exit 1
fi

$DOCKER_COMMAND build -t salaryman-e2e -f "$HERE/Dockerfile" "$HERE"

$DOCKER_COMMAND run --rm \
  -v "${MODELS_DIR}:/models:ro" \
  -e "RUNS=${RUNS:-10}" \
  -e "MIN_SUCCESS=${MIN_SUCCESS:-4}" \
  "$@" \
  salaryman-e2e
