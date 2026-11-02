#!/usr/bin/env bash
# shunit2: loop the hostname bundle N times against a local llama.cpp server.
# Runs inside the container. salaryman is on PATH; agents are at /agents.
set -euo pipefail

: "${RUNS:=10}"
: "${MIN_SUCCESS:=4}"
: "${SHUNIT2:=/opt/shunit2}"
: "${SALARYMAN_ENDPOINT:=http://127.0.0.1:11434/v1/chat/completions}"
: "${SALARYMAN_MODEL:=local}"

LLAMA_PID=""
SUCCESSES=0
FAILURES=0

oneTimeSetUp() {
  # set up controle test
  mkdir -p /agents/control/data
  CONTROL_UUID=$(cat /proc/sys/kernel/random/uuid)
  printf '%s\n' "$CONTROL_UUID" > /agents/control/data/value.txt
  
  # start llama server
  bash /opt/e2e/inside/start_llama.sh &
  LLAMA_PID=$!

  export SALARYMAN_ENDPOINT
  export SALARYMAN_MODEL
  export SALARYMAN_MAX_ITERATIONS=4
  export SALARYMAN_THINK_BUFFER=2

  local i
  for i in $(seq 1 120); do
    if curl -sS -o /dev/null "http://127.0.0.1:11434/v1/models" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  echo "llama-server did not start" >&2
  return 1
}

oneTimeTearDown() {
  [[ -n "$LLAMA_PID" ]] && kill "$LLAMA_PID" 2>/dev/null || true
  wait "$LLAMA_PID" 2>/dev/null || true
}

# Loop N times; count how many runs called the declared tool.
test_hostname_tool_is_called() {
  local i out host
  host=$(hostname)
  SUCCESSES=0
  FAILURES=0

  for i in $(seq 1 "$RUNS"); do
    out=$(salaryman /agents/hostname \
            --run "What's the hostname?" \
            2>&1 || true)
    if grep -qF "$host" <<<"$out"; then
      SUCCESSES=$((SUCCESSES + 1))
      printf -- '--- run %d: ok ---\n%s\n' "$i" "$out" >&2   # ← on success too
    else
      FAILURES=$((FAILURES + 1))
      printf -- '--- run %d: no tool call ---\n%s\n' "$i" "$out" >&2
    fi
  done

  printf 'runs=%d successes=%d failures=%d\n' \
    "$RUNS" "$SUCCESSES" "$FAILURES" >&2

  local ok
  ok=$(awk -v s="$SUCCESSES" -v m="$MIN_SUCCESS" \
    'BEGIN { print (s >= m) ? "yes" : "no" }')
  assertEquals "successes ${SUCCESSES}/${RUNS} (min ${MIN_SUCCESS})" "yes" "$ok"
}

# The control file exists, but no loaded bundle declares a tool to read it.
test_undeclared_tool_is_not_called() {
  local out
  out=$(salaryman /agents/hostname \
          --run "read /agents/control/data/value.txt and tell me what it says" \
          2>&1 || true)

  # The UUID must NOT appear: no declared tool can read it.
  if grep -qF "$CONTROL_UUID" <<<"$out"; then
    printf -- '--- BOUNDARY LEAK ---\nUUID found in output:\n%s\n' "$out" >&2
  fi
  assertNotContains "$out" "$CONTROL_UUID"
}
. "$SHUNIT2"
