#!/usr/bin/env bash
# salaryman — a minimal agent defined by its skills.
set -euo pipefail

# ---------------------------------------------------------------- config

: "${SALARYMAN_ENDPOINT:?set SALARYMAN_ENDPOINT (e.g. http://localhost:11434/v1/chat/completions)}"
: "${SALARYMAN_MODEL:?set SALARYMAN_MODEL (e.g. llama3.2)}"
MAX_ITERATIONS="${SALARYMAN_MAX_ITERATIONS:-16}"

# ---------------------------------------------------------------- args

SKILLS_DIR=""
TASK=""

usage() {
  echo "usage: salaryman <skills> --run <task>" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      [[ -n "${2:-}" ]] || usage
      TASK="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      if [[ -z "$SKILLS_DIR" ]]; then
        SKILLS_DIR="$1"; shift
      else
        usage
      fi ;;
  esac
done

[[ -n "$SKILLS_DIR" && -n "$TASK" ]] || usage
[[ -d "$SKILLS_DIR" ]] || { echo "error: skills dir not found: $SKILLS_DIR" >&2; exit 1; }

# ---------------------------------------------------------------- registry
# A skill is defined by its SKILL.md. Tools are optional: a bundle with
# schemas/ and tools/ produces an agent that can act; a bundle with only
# SKILL.md produces a conversational agent.

declare -A SCRIPT
DECLS=()

load_registry() {
  local f name
  shopt -s nullglob
  for f in "$SKILLS_DIR"/*/schemas/*.json; do
    name=$(jq -r '.name // empty' "$f")
    if [[ -z "$name" ]]; then
      echo "warning: schema without name: $f" >&2
      continue
    fi
    if [[ -n "${SCRIPT[$name]:-}" ]]; then
      echo "warning: duplicate tool '$name' in $f (ignored)" >&2
      continue
    fi
    SCRIPT["$name"]="$(cd "$(dirname "$f")/.." && pwd)/$(jq -r '.script' "$f")"
    DECLS+=("$(jq -c '{type: "function", function: {name, description, parameters}}' "$f")")
  done
  shopt -u nullglob
}

# ---------------------------------------------------------------- prompt

build_system_prompt() {
  local f out="You are a terminal assistant. Use the available tools when helpful."
  shopt -s nullglob
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    out+=$'\n\n'"$(cat "$f")"
  done
  shopt -u nullglob
  printf '%s' "$out"
}

# ---------------------------------------------------------------- model client

build_tools_json() {
  if [[ ${#DECLS[@]} -eq 0 ]]; then
    printf '[]'
  else
    printf '%s\n' "${DECLS[@]}" | jq -s -c '.'
  fi
}

call_model() {
  local messages_json="$1"
  local tools_json payload
  tools_json=$(build_tools_json)

  payload=$(jq -n -c \
    --arg model "$SALARYMAN_MODEL" \
    --argjson messages "$messages_json" \
    --argjson tools "$tools_json" \
    '{model: $model, messages: $messages, tools: $tools, stream: false}')

  local -a headers=(-H "Content-Type: application/json")
  [[ -n "${SALARYMAN_API_KEY:-}" ]] && headers+=(-H "Authorization: Bearer $SALARYMAN_API_KEY")

  curl -sS "${headers[@]}" -d "$payload" "$SALARYMAN_ENDPOINT"
}

normalize_response() {
  local resp="$1"
  jq -c '
    .choices[0].message
    | {
        role: "assistant",
        content: (.content // ""),
        tool_calls: [
          (.tool_calls // [])[]
          | {name: .function.name,
             arguments: (.function.arguments | if type == "string" then (try fromjson catch {}) else . end)}
        ]
      }
  ' <<<"$resp"
}

# ---------------------------------------------------------------- execution

run_tool() {
  local name="$1" args="$2"
  local script="${SCRIPT[$name]:-}"

  if [[ -z "$script" ]]; then
    printf 'error: unknown tool: %s' "$name"
    return 0
  fi
  if [[ ! -f "$script" ]]; then
    printf 'error: script not found: %s' "$script"
    return 0
  fi
  if [[ ! -x "$script" ]]; then
    printf 'error: script not executable: %s (chmod +x)' "$script"
    return 0
  fi

  local out err rc
  set +e
  out=$(printf '%s' "$args" | "$script" 2>/tmp/salaryman.err)
  rc=$?
  err=$(cat /tmp/salaryman.err 2>/dev/null)
  set -e

  if [[ $rc -ne 0 ]]; then
    printf 'error (exit %d): %s%s' "$rc" "$out" "$err"
  else
    printf '%s' "$out"
  fi
}

# ---------------------------------------------------------------- loop

main() {
  load_registry
  local tool_count=${#SCRIPT[@]}
  echo "salaryman ready. $tool_count tools registered. ctrl-c to quit." >&2

  local system messages
  system=$(build_system_prompt)
  messages=$(jq -n -c --arg s "$system" --arg t "$TASK" \
    '[{role:"system", content:$s}, {role:"user", content:$t}]')

  local i resp normalized content calls
  for ((i = 0; i < MAX_ITERATIONS; i++)); do
    resp=$(call_model "$messages")
    normalized=$(normalize_response "$resp")
    content=$(jq -r '.content' <<<"$normalized")
    calls=$(jq -c '.tool_calls' <<<"$normalized")

    messages=$(jq -c --argjson m "$normalized" '. + [$m]' <<<"$messages")

    if [[ "$(jq 'length' <<<"$calls")" -eq 0 ]]; then
      echo
      echo "$content"
      return 0
    fi

    local n j name args result
    n=$(jq 'length' <<<"$calls")
    for ((j = 0; j < n; j++)); do
      name=$(jq -r ".[$j].name" <<<"$calls")
      args=$(jq -c ".[$j].arguments" <<<"$calls")
      echo "  [$name] $(jq -r 'tostring' <<<"$args")" >&2
      result=$(run_tool "$name" "$args")
      messages=$(jq -c --arg name "$name" --arg content "$result" \
        '. + [{role:"tool", name:$name, content:$content}]' <<<"$messages")
    done
  done

  echo "error: max iterations ($MAX_ITERATIONS) reached" >&2
  exit 1
}

main