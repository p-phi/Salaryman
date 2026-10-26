#!/usr/bin/env bash
# Run an allowlisted read-only command. Arguments are JSON on stdin.
set -euo pipefail

ALLOWLIST=(
  "ls" "cat" "head" "tail" "wc" "grep"
  "git status" "git diff" "git log"
)

fail() {
  echo "error: $1" >&2
  echo "allowed: ls, cat, head, tail, wc, grep, git status, git diff, git log" >&2
  exit 1
}

input=$(cat)
command=$(jq -r '.command // empty' <<<"$input")

if [[ -z "$command" ]]; then
  fail 'missing "command". Expected {"command": "<allowed command>"}.'
fi

# Reject shell metacharacters outright: no pipes, redirects, subshells,
# command substitution, sequencing, or backgrounding.
case "$command" in
  *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*|*'$('*|*$'\n'*)
    fail "the command contains a shell metacharacter. A single command is required."
    ;;
esac

# Extract the first token and, for git, the first two.
read -r -a tokens <<<"$command"
first="${tokens[0]:-}"
if [[ "$first" == "git" ]]; then
  second="${tokens[1]:-}"
  verb="git $second"
else
  verb="$first"
fi

allowed=false
for entry in "${ALLOWLIST[@]}"; do
  if [[ "$entry" == "$verb" ]]; then
    allowed=true
    break
  fi
done

if [[ "$allowed" != true ]]; then
  fail "'$verb' is not in the allowlist."
fi

# Run it. The command is a single allowlisted verb with arguments;
# the metacharacter check above has already excluded composition.
set +e
out=$("$SHELL" -c "$command" 2>&1)
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "error (exit $rc): $out" >&2
  exit 1
fi

printf '%s\n' "$out"

