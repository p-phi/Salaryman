#!/usr/bin/env bash
# =============================================================================
# Salaryman
# -----------------------------------------------------------------------------
# A minimal agent defined by its skills.
#
# An agent is a harness plus a skill set. This script is the harness: it loads
# a skills directory, builds a tool registry from the schema files, and runs a
# loop: model -> tool call -> script -> result -> model. There is no general
# invocation path; the model can only ask for tools that a file declares.
#
# Environment:
#   SALARYMAN_ENDPOINT   required; chat-completions URL
#   SALARYMAN_MODEL      required; model name
#   SALARYMAN_API_KEY    optional; bearer token for a hosted provider
#   SALARYMAN_PROVIDER   optional; openai-compatible (default) | responses
#   SALARYMAN_MAX_ITERATIONS  optional; loop cap, default 16
#   SALARYMAN_THINK_BUFFER  optional; loop exit condition buffer
#
# Source: https://github.com/p-phi/salaryman
# License: MIT — see the LICENSE file in the source repo.
# Author: P. Phi
# ============================================================================= 
set -euo pipefail

VERSION="0.0.3"
USAGE_ERROR=1

# ---------------------------------------------------------------- config
# Iteration control
MAX_ITERATIONS="${SALARYMAN_MAX_ITERATIONS:-16}"
# Allows the model to return pure text responses without tools for up to THINK_BUFFER rounds
THINK_BUFFER="${SALARYMAN_THINK_BUFFER:-1}"
# Provider shape (default: OpenAI-compatible)
PROVIDER="${SALARYMAN_PROVIDER:-openai-compatible}"
SPIN_PID=""
API_KEY=${SALARYMAN_API_KEY:-}
# ---------------------------------------------------------------- args

TRACE_MESSAGES=""
TRACE=0
SKILLS_DIR=""
TASK=""
# Usage banner and command-line argument parsing
usage() {
  cat >&2 <<EOF
usage:
  salaryman <skills> --run <task> [--provider <name>]

options:
  --run <task>         run an agent on the given task
  --provider <name>    provider shape (default: openai-compatible)
  --show_config        show the current loaded configuration
  -h, --help           show this help
  -v, --version        show the version
  -t, --trace          stdout = wrapped JSONL trace

providers:
  openai-compatible    OpenAI chat-completions shape (Ollama, Groq, Together, ...)

environment:
  SALARYMAN_ENDPOINT   required; chat-completions URL
  SALARYMAN_MODEL      required; model name
  SALARYMAN_API_KEY    optional; bearer token for a hosted provider
  SALARYMAN_PROVIDER   optional; default provider shape
  SALARYMAN_MAX_ITERATIONS  optional; loop cap, default 16
  SALARYMAN_THINK_BUFFER  optional; max rounds without tool, default 1
EOF
  exit "$USAGE_ERROR"
}
# Display version
version() {
  echo "Salaryman v$VERSION"
  exit 0
}
# Print to stderr
log_stderr(){
  echo "[$1]$2" >&2
}
# Display config
show_config() {
  echo "SALARYMAN_ENDPOINT=$SALARYMAN_ENDPOINT" 
  echo "SALARYMAN_MODEL=$SALARYMAN_MODEL" 
  echo "SALARYMAN_PROVIDER=$PROVIDER" 
  echo "SALARYMAN_MAX_ITERATIONS=$MAX_ITERATIONS" 
  echo "SALARYMAN_THINK_BUFFER=$THINK_BUFFER"   
  exit 0
}
# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      [[ -n "${2:-}" ]] || usage
      TASK="$2"; shift 2 ;;
    --provider)
      [[ -n "${2:-}" ]] || usage
      PROVIDER="$2"; shift 2 ;;
    -h|--help)
      USAGE_ERROR=0
      usage ;;
    -v|--version)
      version ;;
    --show-config)
      show_config ;;
    -t|--trace)
      TRACE=1; shift 1 ;;
    *)
      if [[ -z "$SKILLS_DIR" ]]; then
        SKILLS_DIR="$1"; shift
      else
        usage
      fi ;;
  esac
done

# ---------------------------------------------------------------- trace functions

wrap_message()   { jq -c --arg app "slym" '{app:$app, trace:.}'; }
unwrap_message() { jq -c 'if has("app") and .app=="slym" then .trace else . end'; }
is_slym_trace()  { jq -e 'type=="object" and .app=="slym" and has("trace")' \
                     >/dev/null 2>&1 <<<"$(head -n1)"; }
# PIPE SUPPORT
# ---------------------------------------------------------------- stdin detection
# Two input kinds arrive on stdin, and they mean different things:
#   * a transcript  → resume it (the previous stage's trace becomes our state)
#   * anything else → task text (append to --run, as a plain pipe would)
# The distinction is made by *shape*, not by a flag, so | and < both work and
# need no ceremony. If stdin parses as messages, it is a conversation; if not,
# it is prompt text.
if [[ ! -t 0 ]]; then
  input=$(cat)
  # Separate trace lines from non-trace lines incase of mixed stdin input types
  mapfile -t lines <<<"$input"
  wrapped=(); rest=()
  for line in "${lines[@]}"; do
    if [[ "$line" == '{"app":"slym"'* ]]; then
      wrapped+=("$line")
    else
      rest+=("$line")
    fi
  done
  
  if ((${#wrapped[@]})); then
    TRACE_MESSAGES=$(printf '%s\n' "${wrapped[@]}" | unwrap_message | jq -s -c '.')
  fi
  if ((${#rest[@]})); then
    TASK+=$'\n\n'"$(printf '%s\n' "${rest[@]}")"
  fi
fi

# Validate required args and permissions
[[ -n "$SKILLS_DIR" ]] || usage
[[ -d "$SKILLS_DIR" ]] || { echo "error: skills dir not found: $SKILLS_DIR" >&2; exit 1; }

case "$PROVIDER" in
  openai-compatible|responses) ;;
  *) echo "error: unknown provider: $PROVIDER" >&2; usage ;;
esac

# ---------------------------------------------------------------- registry

declare -A SCRIPT=()
DECLS=()
# Loads all skills into SCRIPT map
load_registry() {
  local f name skillpath="$SKILLS_DIR/*/schemas/*.json"
  if [[ -f "$SKILLS_DIR/SKILL.md" ]]; then
    skillpath="$SKILLS_DIR/schemas/*.json"
  fi
  shopt -s nullglob
  for f in $skillpath; do
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
  local skillpath="$SKILLS_DIR/*/SKILL.md"
  if [[ -f "$SKILLS_DIR/SKILL.md" ]]; then
    skillpath="$SKILLS_DIR/SKILL.md"
  fi
  shopt -s nullglob
  for f in $skillpath; do
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
    # responses)         call_responses "$messages_json" ;;
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

# call_responses() {
#   echo "error: provider 'responses' is not implemented yet." >&2
#   echo "       implement call_responses and normalize_responses." >&2
#   exit 1
# }

post_json() {
  local payload="$1"
  local -a headers=(-H "Content-Type: application/json")
  [[ -n "$API_KEY" ]] && headers+=(-H "Authorization: Bearer $API_KEY")
  curl -sS "${headers[@]}" -d "$payload" "$SALARYMAN_ENDPOINT"
}

normalize_response() {
  local resp="$1"
  case "$PROVIDER" in
    openai-compatible) normalize_openai "$resp" ;;
    # responses)         normalize_responses "$resp" ;;
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
  # Handle error case  
  if jq -e 'has("__error")' >/dev/null <<<"$normalized"; then
    jq -r '.__error' <<<"$normalized" >&2
    return 1
  fi
  # Return cleaned JSON
  printf '%s' "$normalized"
}

# normalize_responses() {
#   echo "error: provider 'responses' is not implemented yet." >&2
#   exit 1
# }

# ---------------------------------------------------------------- execution

run_tool() {
  local name="$1" args="$2"
  local script="${SCRIPT[$name]:-}"

  if [[ -z "$script" ]]; then
    printf 'error: unknown tool: %s' "$name" >&2
    return 1
  fi
  if [[ ! -f "$script" ]]; then
    printf 'error: script not found: %s' "$script" >&2
    return 1
  fi
  if [[ ! -x "$script" ]]; then
    printf 'error: script not executable: %s (chmod +x)' "$script" >&2
    return 1
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
# User feedback loop
thinking_start() {
  [[ -t 2 ]] || return 0
  (
    local t=0
    while :; do
      printf '\rthinking… %ds' "$t" >&2
      sleep 1
      t=$((t+1))
    done
  ) &
  SPIN_PID=$!
}
# Stop the 'thinking' task if running
thinking_stop() {
  [[ -n "${SPIN_PID:-}" ]] || return 0
  kill "${SPIN_PID:-}" 2>/dev/null || true
  wait "${SPIN_PID:-}" 2>/dev/null || true
  SPIN_PID=""
  printf '\r\033[K' >&2
}

# ---------------------------------------------------------------- loop

main() {
  # Validate required vars
  : "${SALARYMAN_ENDPOINT:?set SALARYMAN_ENDPOINT (e.g. http://localhost:11434/v1/chat/completions)}"
  : "${SALARYMAN_MODEL:?set SALARYMAN_MODEL (e.g. llama3.2)}"
  
  # Kill thinking task on exit
  trap 'thinking_stop' EXIT
  
  # Load tools
  load_registry
  # Initialize task messages
  local system messages
  # ---------------------------------------------------------------- messages init
  # Two starting states, chosen by whether stdin supplied a transcript:
  #   * resume   → continue the transcript, append --run as the next user turn.
  #               The trace's system message (index 0) is kept as-is: the trace
  #               is the state, including the persona it was running under.
  #   * fresh    → build system prompt from the bundle's SKILL.md and pair it
  #               with --run as the first user turn.
  system=$(build_system_prompt)
  if [[ -n "$TRACE_MESSAGES" ]]; then
    # trace is pure history (no system); prepend the bundle's system prompt
    messages=$(jq -c \
      --arg s "$system" \
      --arg t "$TASK" \
      '[{role:"system", content:$s}] + . + [{role:"user", content:$t}]' \
      <<<"$TRACE_MESSAGES")
  else
    messages=$(jq -n -c --arg s "$system" --arg t "$TASK" \
      '[{role:"system", content:$s}, {role:"user", content:$t}]')
  fi 
  # Main conversation loop
  local i resp normalized content calls
  local buffer=0
  local answer=()
  for ((i = 0; i < MAX_ITERATIONS; i++)); do 
    thinking_start
    # Call model to get response
    resp=$(call_model "$messages")
    thinking_stop
    # Normalize the response
    normalized=$(normalize_response "$resp")
    content=$(jq -r '.content' <<<"$normalized")
    calls=$(jq -c '.tool_calls' <<<"$normalized")
    if [[ $TRACE -eq 1 ]]; then
      wrap_message <<<"$normalized"
    fi
    # Add response to messages
    messages=$(jq -c --argjson m "$normalized" '. + [$m]' <<<"$messages")

    # Buffer or return based on conditions
    # This allows some models to use tools better
    if [[ "$(jq 'length' <<<"$calls")" -eq 0 ]]; then
      if [[ $TRACE -eq 0 ]]; then
        answer+=("$content")
      fi
      (( buffer +=1 ))
    else
    # A tool call means the run isn't over — discard any text-only turns
    # buffered so far, so `answer` only ever holds the final quiet run.
      answer=()
      buffer=0
    fi
    if [[ $buffer -gt $THINK_BUFFER ]]; then
      if [[ $TRACE -eq 0 ]]; then
        printf '%s\n' "${answer[@]}"
      fi
      return 0
    fi
    # Handle tool calls
    local n j name args call_id result
    n=$(jq 'length' <<<"$calls")
    for ((j = 0; j < n; j++)); do
      name=$(jq -r ".[$j].name" <<<"$calls")
      args=$(jq -c ".[$j].arguments" <<<"$calls")
      call_id=$(jq -r ".[$j].id" <<<"$calls")
      result=$(run_tool "$name" "$args")
      # Reconstruct messages with tool response
      messages=$(jq -c --arg id "$call_id" --arg content "$result" \
        '. + [{role: "tool", tool_call_id: $id, content: $content}]' <<<"$messages")
      if [[ $TRACE -eq 1 ]]; then
        jq -nc --arg id "$call_id" --arg content "$result" \
          '{role:"tool", tool_call_id:$id, content:$content}' \
          | wrap_message
      fi
    done
  done
  # Print final answer if no early exit
  echo "error: max iterations ($MAX_ITERATIONS) reached" >&2
  exit 1
}

main
