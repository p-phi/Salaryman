#!/usr/bin/env bash
# Run a salaryman bundle on a task. Arguments are JSON on stdin.
set -euo pipefail

input=$(cat)
path=$(jq -r '.path // empty' <<<"$input")
task=$(jq -r '.task // empty' <<<"$input")

if [[ -z "$path" ]]; then
  echo 'error: missing "path". Expected {"path": "agents/time", "task": "..."}.' >&2
  exit 1
fi
if [[ -z "$task" ]]; then
  echo 'error: missing "task".' >&2
  exit 1
fi
if [[ ! -d "$path" ]]; then
  echo "error: bundle not found: $path" >&2
  exit 1
fi

exec salaryman "$path" --run "$task"
