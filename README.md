# Salaryman

Salaryman is a minimal agent defined by its skills.

A skill is a fixed prompt that may declare tools. The agent is the set of skills it carries — nothing more. There is no general invocation path: the model can only ask for declared tools, with arguments that fit their schemas. Every action is a typed call to a readable file.

```bash
salaryman skills/pdf-extract --run "what's in report.pdf?"
```

---

## What that means

· The agent is its skills. The system prompt is the skills' prose. The tool registry is the skills' declarations. Nothing else contributes capability or identity.
· A skill is a fixed prompt. Authored, versioned, loaded before execution. The task is the variable part. The agent is the fixed part.
· Tools are optional. A skill with schemas/ and tools/ produces an agent that can act. A skill with only SKILL.md produces a conversational agent — one that helps you decide, but doesn't execute the decision itself. Both are agents.
· No general invocation path. The model can only ask for declared tools. There is no shell, no code interpreter, no way to ask for an arbitrary command. What can execute is bounded by the declarations.

---

## Why

An LLM speaks human language but cannot act. A developer acts through a toolchain, and their work is auditable because every action goes through a reviewable artifact. Salaryman is an attempt to give an LLM a toolchain whose actions are auditable in the same way.

The toolchain is the skill set. The audit unit is the call — which tool, which arguments, against which contract. The model supplies judgment; the skills supply capability; the declarations supply the audit trail. The composite is a developer you can read.

Most agent frameworks do the opposite. They ship a general-purpose executor — a shell, a code interpreter — and add tools on top. The executor is convenient, and it destroys the audit unit: "what the model did" becomes "the model typed this string into bash," which is not reviewable the way a function call is.

Salaryman removes the general invocation path. Every capability is a declared tool — a specific script with a typed argument schema. The set of declared tools is the authority boundary. The agent has exactly the capabilities its skills declare, and every capability is a file you can read.

The harness is written in bash because bash is the native language of the system it runs on. A Unix system speaks processes, pipes, and exit codes; bash speaks exactly that. The harness isn't a layer between the agent and the system — it's the system's own way of invoking things, pointed at declared tools. Writing it in a higher-level language would introduce a translation layer between the harness and the executor, and the design's whole point is that there isn't one. The language is not a limitation; it's the thesis made literal.

---

## A bundle

```
skills/pdf-extract/
  SKILL.md          prose: when and how
  schemas/
    pdf_extract.json
  tools/
    extract.py
```

schemas/pdf_extract.json declares a tool completely:

```json
{
  "name": "pdf_extract",
  "description": "Extract text and tables from a PDF file. Returns markdown.",
  "script": "tools/extract.py",
  "parameters": {
    "type": "object",
    "properties": {
      "path": { "type": "string", "description": "Path to the PDF file." }
    },
    "required": ["path"]
  }
}
```

The harness reads script to know what to run. The model reads name, description, and parameters to know when and how to call it. One file, three jobs.

tools/extract.py receives its arguments as JSON on stdin:

```python
#!/usr/bin/env python3
import sys, json

try:
    args = json.load(sys.stdin)
    path = args["path"]
except (json.JSONDecodeError, KeyError) as e:
    print(f"error: invalid arguments ({e}). "
          f"Expected {{\"path\": \"<path to a PDF>\"}}.", file=sys.stderr)
    sys.exit(1)

print(f"[stub] extracted text from {path}")
```

Scripts are executed directly, so they need a shebang and the executable bit (chmod +x).

What a tool writes on failure is up to the tool — but the model is the reader. The harness only cares about the channel: arguments in on stdin, result on stdout, non-zero exit on failure, output passed through unchanged. It does not parse your errors. The model, however, has to read them to decide what to do next, and an error it can't parse is an error it can't recover from. So write failure output for the model: say what failed and what the caller could do differently.

SKILL.md is prose — when to use the tool, how to interpret the result, what not to do. The harness never parses it. A skill is defined by its SKILL.md; schemas/ and tools/ are optional. A bundle with only SKILL.md is a conversational agent: it reasons and responds, but has no action surface.

A bundle can hold one tool or many. Atomic bundles (one tool, one concern) keep the authority granted visible in the registry; comprehensive bundles (many tools, one domain) reduce the number of files to load but widen the blast radius of a single bundle. Atomic is the default posture; comprehensive is a deliberate choice.

---

## Getting started

```bash
# point at a model
export SALARYMAN_ENDPOINT="http://localhost:11434/v1/chat/completions"
export SALARYMAN_MODEL="llama3.2"

# scaffold a bundle — the init skill uses a model call to interpret the task
salaryman skills/init --run "create a python bundle at skills/my-tool"

# run it
salaryman skills/my-tool --run "say hello"
```

```
salaryman ready. 1 tool registered. ctrl-c to quit.

> say hello
  [my_tool] {"text":"hello"}
  my_tool received: hello
```

The scaffolder is a skill like any other: skills/init declares a write_bundle tool, and the agent calls it. That's the demonstration — the tool's own authoring mode, running through the loop, expressed as a bundle.

If you want the deterministic path, the templates are there:

```bash
cp -r skills/init/templates/bundle skills/my-tool
# rename the placeholders by hand
```

Both paths are documented. Neither is hidden.

---

## The model

Ollama, through its OpenAI-compatible endpoint. Two environment variables:

```bash
export SALARYMAN_ENDPOINT="http://localhost:11434/v1/chat/completions"
export SALARYMAN_MODEL="llama3.2"
```

SALARYMAN_API_KEY is optional (Ollama doesn't need one; a hosted provider would).

Bundles are provider-neutral: the schema is common-subset JSON Schema (type, properties, required, description). The client wraps it in the provider's envelope and normalizes the response to {name, arguments}, so the loop never sees provider specifics. Adding a provider is a branch in the client, not a change to any bundle.

---

## Design principles

· The agent is its skills. Everything follows from this.
· A skill is a fixed prompt. Tools are optional. A skill without tools is a conversational agent.
· The registry is the authority. No capability exists unless a schema file declares it. There is no general invocation path.
· Fixed scripts, typed arguments. The model supplies arguments, not commands.
· Bundles are provider-neutral. Provider translation lives in the client, nowhere else.
· The harness trusts the skill. No argument validation, no sandboxing. A skill that declares {path: string} and crashes on a missing path needs a better script — not a harness that needs a validator.
· The model is the reader. The framework doesn't dictate error shape, but errors it can't read are errors it can't recover from.
· Read it before you run it. A bundle is code. Installing one is trusting it.

---

Status

Early. The loop, the loader, the self-describing schema, and the Ollama client are the interesting parts. The scaffolder is a bundle; the tool builds itself. If you build a bundle, add a provider, or port the harness, the design is the contribution and the code is the proof.

License

MIT.
