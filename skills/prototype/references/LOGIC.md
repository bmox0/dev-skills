# Logic Prototype

A tiny terminal app that lets the user drive a state model by hand — for
questions about business logic, state transitions or data shape that only
feel wrong once pushed through real cases: "does this state machine handle X
then Y", "can this data model represent case Z", "what should this API look
like".

## Process

1. **State the question**, one paragraph, in the prototype's README or a
   top-of-file comment — a prototype that answers the wrong question is pure
   waste.
2. **Pick the language**: whatever the host project uses; no new package
   manager or runtime for the prototype. Ask if the project has no obvious
   runtime.
3. **Isolate the logic in a portable, pure module** — no I/O, no terminal
   code, no `console.log` for control flow — so it can be lifted into the
   real codebase once the question is answered. Pick whichever shape fits the
   question:
   - A pure reducer, `(state, action) => state`, for discrete actions over a
     single state value.
   - A state machine, for when "which actions are legal now" is part of the
     question.
   - A small set of pure functions, when there's no implicit current state.
   - A class or module with a clear method surface, when the logic owns
     ongoing internal state.
4. **Build the smallest TUI that exposes it**: on every tick, clear the
   screen and redraw one frame — current state pretty-printed (bold field
   names, dim secondary context), then the keyboard shortcuts available.
   Initialise state, render, read one keystroke at a time, dispatch to a
   handler, re-render the full frame after every action, loop until quit.
5. **Make it runnable in one command**, kept under
   `.ai-workflow/prototypes/`, with that command at the top of the main file
   — the project's task runner stays untouched.
6. **Hand it over**: give the user the run command and let them drive it. The
   moments they say "wait, that shouldn't be possible" are bugs in the idea.
   Add actions if they ask.
7. **Capture the answer** the way [SKILL](../SKILL.md) describes: the plan
   links the prototype, a phase lifts the validated reducer / machine /
   function set into the real module, and the TUI shell stays under
   `.ai-workflow/prototypes/`.

## Anti-patterns

- No tests — a prototype that needs them is no longer a prototype.
- No real database — an in-memory store, unless persistence is the question.
- No generalising beyond the one question being asked.
- Keep the logic and the TUI apart: if the pure module references
  `console.log` or terminal escape codes, it isn't portable anymore.
