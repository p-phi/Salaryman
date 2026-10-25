#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
rel=$(jq -r '.path // empty' <<<"$input")
[[ -n "$rel" ]] || { echo 'error: missing "path".' >&2; exit 1; }

root=$(cd "${SALARYMAN_SKILLS:-$PWD}" && pwd)
target=$(cd "$root" && realpath -m -- "$rel")

case "$target" in
  "$root"/*) ;;
  *) echo "error: path escapes the skills directory: $rel" >&2; exit 1 ;;
esac

[[ -f "$target" ]] || { echo "error: not a file: $rel" >&2; exit 1; }

chmod +x "$target"
echo "made executable: $rel"

