---
name: prototype
description: Build a throwaway prototype to answer a design question before the plan — how something looks, sits or moves, or whether a state model feels right. Offered after a grill or a discussion; the human decides.
---

# Prototype

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).
Use the current [task paths](../../references/WORKFLOW-PATHS.md) before handing
work to a prototype author.

After a grill or discussion, offer a prototype in one line. "A prototype?
An HTML file, inside the app with real data, or code
for the logic?" The human picks a shape or declines. This session is the
orchestrator: a worker draws, it does not. A prototype is throwaway code that
answers one question, in the shape the human picked:

- **An HTML file:** one self-contained file with the variants on a floating
  bottom switcher, each variant showing its full state.
- **Inside the app:** the variants on the page the human names, with its real
  data, behind `?variant=`: [UI.md](references/UI.md).
- **Code:** a tiny terminal app that pushes a logic or state model through the
  hard cases: [LOGIC.md](references/LOGIC.md).

## A worker draws it

Dispatch a secondary subagent with the question, the shape and the variants in the
human's words, and the output path in the task's `prototypes` artifacts:
`YYYY-MM-DD-<topic>.html` for the HTML file, a `YYYY-MM-DD-<topic>/` directory
for code. It draws what it is handed and never designs: a control, a screen or
wording the conversation never named comes back as a question, not an
invention. Nothing reaches outside the HTML file: no remote script, style, font
or image. Confirm Git ignores the output before writing.

Open it for the human yourself: `open <path>` on macOS, `xdg-open <path>`
elsewhere.

## Rules

1. **Throwaway, and marked as such.** Prototype code inside the app sits next
   to what it prototypes and is named so a reader sees it is a prototype.
2. **One command runs it**, with the project's own runtime.
3. **No persistence** unless persistence is the question. **No polish:** no
   tests, no abstractions.
4. **Capture the answer.** Save progress with `runweld prototype save`.
   Record the human's choice and artifact with `runweld prototype done`, or
   `runweld prototype skip --reason TEXT`. Remove in-app prototype code.
5. Use the `next` command for planning.
