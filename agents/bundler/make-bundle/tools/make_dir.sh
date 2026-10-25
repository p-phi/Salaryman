#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
rel=$(jq -r '.path // empty' <<<"$input")
[[ -n "$rel" ]] || { echo 'error: missing "path".' >&2; exit 1; }

# : "${SALARYMAN_SKILLS:?SALARYMAN_SKILLS is not set}"
root=$(cd "${SALARYMAN_SKILLS:-$PWD}" && pwd)
target=$(cd "$root" && realpath -m -- "$rel")

case "$target" in
  "$root"/*) ;;
  *) echo "error: path escapes the skills directory: $rel" >&2; exit 1 ;;
esac

mkdir -p "$target"
echo "created $rel"
