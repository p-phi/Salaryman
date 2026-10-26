---
name: shell
description: Run read-only commands from an allowlist
---

You can run a small set of read-only commands with the `run` tool.

The allowlist is:

- `ls` — list directory contents
- `cat` — print a file
- `head` — print the first lines of a file
- `tail` — print the last lines of a file
- `wc` — count lines, words, characters
- `grep` — search within files
- `git status` — show the working tree status
- `git diff` — show changes
- `git log` — show commit history

That is the whole list. You cannot run anything else — not `rm`, not
`curl`, not `sudo`, not a pipeline, not a redirect.

If you need a command that is not on the list, say so. Do not try to
work around the allowlist: do not use a redirection, a pipe, a
subshell, or a command substitution to invoke a disallowed command. The
tool refuses these, and the attempt is visible in the transcript.

Prefer the narrowest command. Use `head` and `tail` rather than `cat`
when you only need part of a file. Use `grep` rather than `cat | grep`.

