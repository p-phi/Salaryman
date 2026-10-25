---
name: make-bundle
description: Produce a new skill bundle from a task description
---

You are a bundle maker. Read the format below, then produce a bundle for
the task.

## The format

A bundle is a directory containing:

- `SKILL.md` — required. Frontmatter with `name` and `description`, then
  a prose body that says when and how to use the tools.
- `schemas/*.json` — optional. Each file declares one tool.
- `tools/*` — optional, but required if a schema exists. The scripts.

`SKILL.md` says *when* to use the tools. The schema declares *what* a
tool is. The script *does* it. The three are linked by the tool's
`name`, which appears in the prose, in the schema, and in the model's
tool call. The name must match in all three places.

## What a tool is

A tool is a declared process. The harness runs the script when the model
asks for it. The script:

- reads its arguments as JSON on stdin
- writes its result to stdout
- signals failure with a non-zero exit code and a message on stderr

It can be written in any language with a shebang. Shell is the default.
The script must be executable (`chmod +x`).

The contract is the channel, not the shape: the script can print
anything, and the harness passes it through. On failure, write for the
model — say what failed and what the caller could do differently.

## The `SKILL.md` template

```markdown
---
name: <bundle-name>
description: <one line: when to use this bundle>
---

<Prose: when to call which tool, how to interpret the result, what not
to do. Name each tool exactly as it appears in its schema.>

```

## The schema template

```json
{
  "name": "<snake_case_tool_name>",
  "description": "<what the tool does, and when to use it>",
  "script": "tools/<tool_name>.sh",
  "parameters": {
    "type": "object",
    "properties": {
      "<arg>": { "type": "string", "description": "<what it is>" }
    },
    "required": ["<arg>"]
  }
}
```

Rules for parameters:

- Use only the common JSON Schema subset: type, properties, required, description, enum, items. Do not use oneOf, anyOf, $ref, patternProperties.
- The script path is relative to the bundle root, not to schemas/.
- The tool name is snake_case; the script's stem is usually the same.

The script template

```bash
#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
arg=$(jq -r '.<arg> // empty' <<<"$input")

if [[ -z "$arg" ]]; then
  echo 'error: missing "<arg>". Expected {"<arg>": "<value>"}.' >&2
  exit 1
fi

echo "result for $arg"
```

Your task

Produce a bundle for the task. Write SKILL.md, one or more schemas,
and the scripts. Use make_dir to create the directory structure and
write_file for each file. After writing each script, call
make_executable on it.

The bundle is created under the skills directory the agent is running
in. Write paths relative to that directory, e.g.
my-tool/SKILL.md, my-tool/schemas/foo.json,
my-tool/tools/foo.sh.

Report the files you created.
