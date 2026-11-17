This is history; the rules that hold now are in `docs/spec/`.

# Plan: Clarify the separate build session and original orchestrator

## Result

The current instructions leave session ownership and the transition after a plan ambiguous. In Claude Code and Codex, the original discussion session remains the user's orchestrator. On the user's instruction to start, it opens a new herdr tab in the same workspace and starts the existing build there. Human review and feedback stay in the original conversation.

## Approach

Clarify the existing skills through one shared session reference and short context pointers. Keep the pipeline CLI, state, phases, gates and native execution roles intact. The independent build session owns its normal graph and reports back; the original session watches it, opens the result at the human gate, and relays the user's words and approvals.

- A new tab in the same workspace for every build, regardless of size — this is the user's established workflow.
- A user instruction starts the build; compiling the plan alone does not — remove the competing automatic-start wording. An already supplied start instruction needs no repeated permission request.
- Launch the same agent host in an independent root session, with no silent Claude defaults for Codex — native Codex children cannot dispatch the build's own agents.
- Keep mechanics in one reference and use herdr's installed CLI documentation — no new launch script, session schema or scheduler.
- Preserve one writer for pipeline state — the build session operates the CLI; the original watches and relays.

## Out of scope

- Changes to pipeline.py, hooks, native execution roles or gate checks.
- A new orchestration framework, background service or herdr implementation.
- Version bumps, merges, releases and pushes.

## Done and Spec

```text
## Done

1. In either host, compile a plan without a start instruction, then give the instruction to start → compilation alone launches nothing; the original session creates a new tab in the same herdr workspace and starts an independent same-host build session from the plan and run file, without asking current versus new. — you check
2. The separate session reaches the human gate → it reports the gate and concrete review location to the original session and waits; the original alerts the user and opens what needs checking, without approving the result itself. — you check
3. The user gives review notes, then requests a round or approves finish in the original conversation → the same build session receives the words unchanged and performs the existing CLI flow only on that user instruction; neither a second build nor duplicate state writes are started. — you check
4. Review the changed tree → pipeline.py, hooks, manifests, gate checks and native role definitions are unchanged; scripts/check and scripts/test pass, and no instruction retains automatic build after planning or same-session builds for small tasks. — you check

## Spec

+ build#separate-build-session — On the user's start instruction, the original session launches build in a new herdr tab in the same workspace and remains the user's orchestrator
  Why: the user's established workflow separates discussion context from execution without moving the conversation
  Done: 1
+ build#gate-through-original-session — The build session waits at the human gate while the original session alerts the user and opens the review location
  Why: the user reviews and responds in the original conversation
  Done: 2
+ build#feedback-through-original-session — The original session relays the user's notes and approvals unchanged to the existing build session, which alone advances pipeline state
  Why: one conversation and one state writer prevent lost feedback and duplicate execution
  Done: 3
```
