---
name: run-bundle
description: Run another salaryman bundle on a task
---

You can run another salaryman agent with the `run_bundle` tool.

`run_bundle` takes two arguments:

- `path` — the bundle's skills directory, e.g. `agents/time`.
- `task` — the task to hand to that agent, e.g. "what time is it?".

The tool runs `salaryman <path> --run "<task>"` and returns the agent's
final answer. That agent has its own skills and its own tools; you do not
see its transcript, only its answer.

Use it when the task needs a capability you do not have — when the
answer requires a tool that is not in your registry, and a bundle that
has it exists.

Do not use it to re-run a task you can already answer: it starts a new
agent with a fresh context, and the answer comes back as a string.

If the path does not exist, the tool fails and tells you so.
