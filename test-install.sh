#!/usr/bin/env bash
set -euo pipefail

${DOCKER_COMMAN:-podman} run --rm -v "$PWD/install.sh:/home/tester/install.sh:ro" \
  debian:bookworm-slim \
  bash -c 'apt-get update && apt-get install -y curl ca-certificates sudo >/dev/null && PATH="$HOME/.local/bin:$PATH" && bash /home/tester/install.sh --unattended && salaryman -v'
