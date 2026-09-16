---
name: bootstrap
description: Injected at session start. States one rule — do not start building a task silently — and names the entries that exist.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to do a specific job, ignore this. Your
brief is your instructions.
</SUBAGENT-STOP>

# Before you start building

There is a workflow in this environment for turning a task into reviewed,
integrated code. Most of it you may reach for yourself. The two that spend real
money and rewrite history are the human's to start.

## The one rule

```text
a pinpoint edit in a place the human named   → just do it
anything that looks like a task              → stop and offer the route
```

Do not begin implementing a task off a bare prompt. Say what you would reach for,
and let them call it:

> "This looks like a task rather than a one-line edit. `{{SKILL:grill}}` to work out
> what we're building, then `{{SKILL:plan}}` — say the word."

## The two you cannot start

`{{SKILL:implement}}` and `{{SKILL:finish}}` **only start because the human
said so.** This is a fact about the environment, not a rule you are being asked
to respect: in every host this repository runs in, only a message from the
human — never a decision you make on your own — starts one of these two.

So when a run should start, name the skill and stop:

> "That's the plan done. `{{SKILL:implement}}` when you're ready."

**Do not read the skill, do not grep for it, and do not work out why the call
failed.** The failed call is cheap; the investigation that follows it is not, and
it buys nothing — the answer is always this paragraph.

The boundary between "pinpoint edit" and "task" is your judgement, and it will
sometimes be wrong. It is a cheap kind of wrong: it shows up as one unnecessary
question, not as a context filled with work nobody asked for.

## What exists

Entries — the human types one, and you may also reach for these yourself when
the request plainly calls for one:

| | |
|---|---|
| `{{SKILL:grill}}` | the task is not clear yet; interview it into a shared understanding |
| `{{SKILL:grill-with-docs}}` | same, and it also captures vocabulary and earned ADRs |
| `{{SKILL:bug}}` | a bug: reproduce, find the cause, pin it with a failing test |
| `{{SKILL:scout}}` | explain how existing code works; read-only |
| `{{SKILL:refactor}}` | restructure, migrate, upgrade — behaviour must not change |
| `{{SKILL:tests}}` | the tests are the deliverable: cover code, or repair tests that lie |
| `{{SKILL:setup}}` | generates the roles a run dispatches — same as `{{SKILL:implement}}` and `{{SKILL:finish}}`, only the human starts it |

Then the pipeline: `{{SKILL:epic}}` (only when the work needs more than one plan) →
`{{SKILL:plan}}` → `{{SKILL:implement}}` → `{{SKILL:finish}}`. The last two are
the ones described above: you name them, you do not call them.

Outside a run: `{{SKILL:review}}`, `{{SKILL:improve}}`, `{{SKILL:research}}`, `{{SKILL:prototype}}`,
`{{SKILL:domain-modeling}}`, `{{SKILL:browser-test}}`.

`{{SKILL:bug}}` is the one you should be quickest to reach for — a bug arrives as
a symptom, and the mistake it prevents happens in the first reply.

The human's instructions — `{{PROJECT_INSTRUCTIONS_FILE}}`, and whatever they just
said — outrank all of this.
