#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
rel=$(jq -r '.path // empty' <<<"$input")
content=$(jq -r '.content // empty' <<<"$input")
[[ -n "$rel" ]] || { echo 'error: missing "path".' >&2; exit 1; }
[[ -n "$content" ]] || { echo 'error: missing or empty "content".' >&2; exit 1; }

# : "${SALARYMAN_SKILLS:?SALARYMAN_SKILLS is not set}"
root=$(cd "${SALARYMAN_SKILLS:-$PWD}" && pwd)
target=$(cd "$root" && realpath -m -- "$rel")

case "$target" in
  "$root"/*) ;;
  *) echo "error: path escapes the skills directory: $rel" >&2; exit 1 ;;
esac

mkdir -p "$(dirname "$target")"
printf '%s\n' "$content" > "$target"
echo "wrote $rel"
