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

> "This looks like a task rather than a one-line edit. `dev-skills:grill` to work out
> what we're building, then `dev-skills:plan` — say the word."

## The two you cannot start

`dev-skills:implement` and `dev-skills:finish` are **absent from your tool list by
design.** This is a fact about the environment, not a rule you are being asked to
respect: the call fails because the skill is not there to call.

So when a run should start, name the skill and stop:

> "That's the plan done. `dev-skills:implement` when you're ready."

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
| `dev-skills:grill` | the task is not clear yet; interview it into a shared understanding |
| `dev-skills:grill-with-docs` | same, and it also captures vocabulary and earned ADRs |
| `dev-skills:bug` | a bug: reproduce, find the cause, pin it with a failing test |
| `dev-skills:scout` | explain how existing code works; read-only |
| `dev-skills:refactor` | restructure, migrate, upgrade — behaviour must not change |
| `dev-skills:tests` | the tests are the deliverable: cover code, or repair tests that lie |

Then the pipeline: `dev-skills:epic` (only when the work needs more than one plan) →
`dev-skills:plan` → `dev-skills:implement` → `dev-skills:finish`. The last two are
the ones described above: you name them, you do not call them.

Outside a run: `dev-skills:review`, `dev-skills:improve`, `dev-skills:research`, `dev-skills:prototype`,
`dev-skills:domain-modeling`, `dev-skills:browser-test`.

`dev-skills:bug` is the one you should be quickest to reach for — a bug arrives as
a symptom, and the mistake it prevents happens in the first reply.

The human's instructions — `CLAUDE.md`, and whatever they just said — outrank all
of this.
