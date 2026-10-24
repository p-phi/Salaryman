# Salaryman

**A minimal agent defined by its skills.**

A skill is a fixed prompt that may declare tools. The agent is the set of skills it carries — nothing more. There is no general invocation path: the model can only ask for declared tools, with arguments that fit their schemas. Every action is a typed call to a readable file.

---

## Getting started

```bash
curl -fsSL https://raw.githubusercontent.com/p-phi/salaryman/main/install.sh | bash
```

Installs salaryman to ~/.local/bin, installing curl and jq first if missing. Add --unattended to skip the prompt; read the script with | less first.

Then point it at a model:

```bash
export SALARYMAN_ENDPOINT="http://localhost:11434/v1/chat/completions"
export SALARYMAN_MODEL="llama3.2"
```

And run a bundle:

```bash
salaryman skills/shell --run "what's in this repository?"
```

```
salaryman ready. 1 tool registered. ctrl-c to quit.

> what's in this repository?
  [run] {"command":"ls -la"}
  total 24
  drwxr-xr-x  8 user user 4096 Oct 24 09:12 .
  ...
  This repository contains a bash agent harness with a skills directory...
```

Dependencies: bash, curl, jq — plus whatever a tool script invokes (git for the shell bundle's git commands, python3 for a Python tool).

---

Architecture

A harness, a skills directory, and a loop:

```
harness (250 lines of bash)
  ├─ loads skills/*/SKILL.md    → system prompt
  ├─ loads skills/*/schemas/    → tool registry
  └─ loop: model → tool call → script → result → model
```

Four decisions follow from that shape:

· No general invocation path. The registry is the authority. There is no shell, no eval, no arbitrary command. The model can only ask for declared tools.
· A skill is a fixed prompt. Tools are optional. A bundle with only SKILL.md is a conversational agent.
· The harness trusts the skill. No validation, no sandboxing. A tool that can't handle a bad argument needs a better script.
· Bundles are provider-neutral. Provider translation is a branch in the client, not a change to any bundle.

Composition is a salaryman. There is no plugin API and no marketplace. A bundle whose tool runs another salaryman composes them; a new feature is a bundle, and a composition of features is a bundle that calls bundles. The unit of composition is the same as the unit of execution.

A manager, in full:

```
skills/manager/
  SKILL.md        # lists its reports: shell (inspect), init (scaffold)
  tools/
    delegate.sh   # salaryman skills/<name> --run "<task>"
```

```bash
salaryman skills/manager --run "inspect this repo and scaffold the missing tool"
```

```
[delegate] {"agent":"shell","task":"what's in this repo?"}
[delegate] {"agent":"init","task":"scaffold a bundle for the missing tool"}
created skills/xyz (shell)
```

The manager reads its reports' descriptions, decides what to route to, and calls salaryman for each. Two calls, two bundles, one outcome — and the routing is visible in the transcript.

The catalog is a SKILL.md. A manager knows its reports because they are listed in its prompt, not because it discovers them. Adding a report means editing the manager — a skill edit, and the self-editing bundle is the mechanism for that.

What it does not do: no sandboxing, concurrency, retries, or streaming. No config format, no plugin API, no ecosystem to install. Ollama is the only wired-up provider. It is small enough to read in one sitting, and every capability is a file.

---

A bundle

```
skills/shell/
  SKILL.md          prose: when and how
  schemas/
    run.json
  tools/
    run.sh
```

schemas/run.json declares a tool completely:

```json
{
  "name": "run",
  "description": "Run a single read-only command from the allowlist. No pipes, redirects, subshells, or command substitution.",
  "script": "tools/run.sh",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "A single command from the allowlist, e.g. 'ls -la', 'cat README.md', 'git status'."
      }
    },
    "required": ["command"]
  }
}
```

The harness reads script to know what to run. The model reads name, description, and parameters to know when and how to call it. One file, three jobs.

tools/run.sh receives its arguments as JSON on stdin, checks the command against the allowlist, and runs it:

```bash
#!/usr/bin/env bash
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
[[ -n "$command" ]] || fail 'missing "command".'

case "$command" in
  *'|'*|*'&'*|*';'*|*'<'*|*'>'*|*'`'*|*'$('*)
    fail "the command contains a shell metacharacter." ;;
esac

read -r -a tokens <<<"$command"
verb="${tokens[0]:-}"
[[ "$verb" == "git" ]] && verb="git ${tokens[1]:-}"

allowed=false
for entry in "${ALLOWLIST[@]}"; do
  [[ "$entry" == "$verb" ]] && allowed=true && break
done
[[ "$allowed" == true ]] || fail "'$verb' is not in the allowlist."

"$SHELL" -c "$command"
```

The schema is shaped like a general shell. The script is not. The narrowness is in the script, and the script is readable.

SKILL.md is prose — when to use the tool, how to interpret the result, what not to do:

```markdown
---
name: shell
description: Run read-only commands from an allowlist
---

You can run a small set of read-only commands with the `run` tool.

The allowlist is: ls, cat, head, tail, wc, grep, git status, git diff,
git log.

That is the whole list. You cannot run anything else — not `rm`, not
`curl`, not a pipeline, not a redirect.

If you need a command that is not on the list, say so. Do not try to
work around the allowlist.
```

The harness never parses SKILL.md; it concatenates it into the system prompt.

A skill is defined by its SKILL.md; schemas/ and tools/ are optional. A bundle with only SKILL.md is a conversational agent — it reasons and responds, but has no action surface.

---

What a tool writes on failure

The harness only cares about the channel: arguments in on stdin, result on stdout, non-zero exit on failure. It does not parse your errors. But the model is the reader — an error it can't parse is an error it can't recover from.

So write failure output for the model: say what failed, and what the caller could do differently. The shell bundle's fail() does exactly that:

```
error: 'rm' is not in the allowlist.
allowed: ls, cat, head, tail, wc, grep, git status, git diff, git log
```

The model reads it, picks an allowed command, and continues.

---

The model

Bundles are provider-neutral: the schema is common-subset JSON Schema (type, properties, required, description). The client wraps it in the provider's envelope and normalizes the response to {name, arguments}. Adding a provider is a branch in the client, not a change to any bundle.

SALARYMAN_API_KEY is optional; set it for a hosted provider that requires a bearer token.

---

Status

Early. The loop, the loader, the self-describing schema, and the Ollama client are the interesting parts. If you build a bundle, add a provider, or port the harness, the design is the contribution and the code is the proof.

License

MIT.



6. **The model** — provider-neutrality, the optional API key.
7. **Status and License.**

The "note on why" is cut. If you want it back, it goes after "The model" and before "Status," as three short paragraphs on auditability, bash-as-native, and the legibility bet.