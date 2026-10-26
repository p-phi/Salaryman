#!/usr/bin/env bash
# salaryman — a minimal agent defined by its skills.
set -euo pipefail

VERSION="0.0.1"

# ---------------------------------------------------------------- config

: "${SALARYMAN_ENDPOINT:?set SALARYMAN_ENDPOINT (e.g. http://localhost:11434/v1/chat/completions)}"
: "${SALARYMAN_MODEL:?set SALARYMAN_MODEL (e.g. llama3.2)}"
MAX_ITERATIONS="${SALARYMAN_MAX_ITERATIONS:-16}"
PROVIDER="${SALARYMAN_PROVIDER:-openai-compatible}"

# ---------------------------------------------------------------- args

SKILLS_DIR=""
TASK=""

usage() {
  cat >&2 <<EOF
usage:
  salaryman <skills> --run <task> [--provider <name>]

providers (shapes):
  openai-compatible   OpenAI chat-completions shape (Ollama, Groq, Together, ...)
  responses           OpenAI Responses API shape
EOF
  exit 1
}

version() {
  echo "Salaryman v$VERSION"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      [[ -n "${2:-}" ]] || usage
      TASK="$2"; shift 2 ;;
    --provider)
      [[ -n "${2:-}" ]] || usage
      PROVIDER="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    -v|--version)
      version ;;
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

case "$PROVIDER" in
  openai-compatible|responses) ;;
  *) echo "error: unknown provider: $PROVIDER" >&2; usage ;;
esac

# ---------------------------------------------------------------- registry

declare -A SCRIPT=()
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
  case "$PROVIDER" in
    openai-compatible) call_openai_compatible "$messages_json" ;;
    responses)         call_responses "$messages_json" ;;
  esac
}

call_openai_compatible() {
  local messages_json="$1"
  local tools_json payload wire_messages
  tools_json=$(build_tools_json)

  wire_messages=$(jq -c '
    [ .[] | if .tool_calls then
        .tool_calls = [ .tool_calls[] | {
          id: .id,
          type: "function",
          function: {name: .name, arguments: (.arguments | tojson)}
        } ]
      else . end ]
  ' <<<"$messages_json")

  payload=$(jq -n -c \
    --arg model "$SALARYMAN_MODEL" \
    --argjson messages "$wire_messages" \
    --argjson tools "$tools_json" \
    '{model: $model, messages: $messages, tools: $tools, stream: false}')

  post_json "$payload"
}

call_responses() {
  echo "error: provider 'responses' is not implemented yet." >&2
  echo "       implement call_responses and normalize_responses." >&2
  exit 1
}

post_json() {
  local payload="$1"
  local -a headers=(-H "Content-Type: application/json")
  [[ -n "${SALARYMAN_API_KEY:-}" ]] && headers+=(-H "Authorization: Bearer $SALARYMAN_API_KEY")
  curl -sS "${headers[@]}" -d "$payload" "$SALARYMAN_ENDPOINT"
}

normalize_response() {
  local resp="$1"
  case "$PROVIDER" in
    openai-compatible) normalize_openai "$resp" ;;
    responses)         normalize_responses "$resp" ;;
  esac
}

normalize_openai() {
  local resp="$1"
  local normalized
  normalized=$(jq -c '
    if (.choices // null) == null then
      {__error: (.error.message // "no choices in response")}
    else
    .choices[0].message
    | {
        role: "assistant",
        content: (.content // ""),
        tool_calls: [
          (.tool_calls // [])[]
          | {
              id: .id,
              name: .function.name,
              arguments: (.function.arguments | if type == "string" then (try fromjson catch {}) else . end)
            }
        ]
      }
    end
    ' <<<"$resp")
  
  if jq -e 'has("__error")' >/dev/null <<<"$normalized"; then
    jq -r '.__error' <<<"$normalized" >&2
    return 1
  fi
  printf '%s' "$normalized"
}

normalize_responses() {
  echo "error: provider 'responses' is not implemented yet." >&2
  exit 1
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
  printf "%s\n\n" "salaryman ready. provider: $PROVIDER. $tool_count tools registered. ctrl-c to quit." >&2

  printf "%s\n" "> $TASK" >&2

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

    local n j name args call_id result
    n=$(jq 'length' <<<"$calls")
    for ((j = 0; j < n; j++)); do
      name=$(jq -r ".[$j].name" <<<"$calls")
      args=$(jq -c ".[$j].arguments" <<<"$calls")
      call_id=$(jq -r ".[$j].id" <<<"$calls")
      echo "  [$name] $(jq -r 'tostring' <<<"$args")" >&2
      result=$(run_tool "$name" "$args")
      messages=$(jq -c --arg id "$call_id" --arg content "$result" \
        '. + [{role: "tool", tool_call_id: $id, content: $content}]' <<<"$messages")
    done
  done

  echo "error: max iterations ($MAX_ITERATIONS) reached" >&2
  exit 1
}

main
