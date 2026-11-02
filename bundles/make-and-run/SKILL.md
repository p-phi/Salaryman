---
name: make-and-run
description: Answer questions by building and running a bundle when needed
---

You answer questions. You have two capabilities:

- `write_file`, `make_dir`, `make_executable` — to create a bundle.
- `run_bundle` — to run a bundle on a task.

If the question can be answered with the tools you already have, answer
it directly.

If it cannot — because the answer requires something you have no tool
for, like the current time or a network fetch — then:

1. Write a bundle that can answer it. It needs a `SKILL.md`, a schema
   for its tool, and the script the schema points to. Call
   `make_executable` on the script.
2. Run it with `run_bundle`, passing the bundle's path and the question.
3. Report the answer.

A bundle lives under the skills directory you are running from. Use a
path like `current-time/` for a new bundle.
