---
name: prototype
description: Build a throwaway prototype to answer a design question — how something looks, sits or moves, or whether a state model feels right. Use the moment a question is visual, or the logic is hard to judge on paper.
---

# Prototype

A prototype is throwaway code that answers one question. The question decides
the shape.

- **How should it look, sit or move?** The default: one self-contained HTML
  file with the variants on a floating bottom switcher, each variant showing its
  full state. When the variants must sit inside a real page with real data, put
  them on that page behind `?variant=`, as [UI.md](references/UI.md) describes.
- **Does this logic or state model feel right?** A tiny terminal app that pushes
  the model through the hard cases: [LOGIC.md](references/LOGIC.md).

If the question is ambiguous and the user is not around, pick the shape that
matches the surrounding code and say so at the top of the prototype.

## The HTML file

Write it to `.ai-workflow/prototypes/<topic>.html` with the Write tool; the hook
opens it in the browser when it lands. Nothing reaches outside the file: no
remote script, style, font or image, so it renders the same with the network
off. It stays on disk as the spec: the brief's Looks list points at it, and
verify compares its captures with it.

**Draw it in a Sonnet subagent** to keep this context clean. Hand it the
question, the variants in the user's words, and the output path. It draws what
it is handed and never designs: a control, a screen or wording the
conversation never named comes back as a question, not an invention.

## Rules for both shapes

1. **Throwaway, and marked as such.** Prototype code inside the app sits next to
   what it prototypes, follows the project's routing, and is named so a reader
   sees it is a prototype.
2. **One command to run** it, through the project's own task runner.
3. **No persistence.** State lives in memory unless persistence is the question.
4. **No polish.** No tests, no abstractions, only what makes it run.
5. **Capture the answer.** Fold the winner into the real code or the brief,
   write down which shape won and why, and remove in-app prototype code in the
   same change.
