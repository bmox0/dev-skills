This is history; the rules that hold now are in `docs/spec/`.

# Plan: advisory hooks and the 5.1.0 release

## Result

A compacted or resumed orchestrator has lost the run's state, a hand edit of a rendered file is drift that later writes refuse, and the docs still describe 5.0. After this plan, in both hosts, a session that starts, resumes or is compacted gets `status` of the plans in flight, an edit of a plan's rendered or state file is answered with the command that makes that change, and the docs describe 5.1, shipped as 5.1.0.

## Approach

The epic's Interfaces and the Approaches of plans 1–4 are the contract. Phase 1 writes the hooks, phase 2 the docs, phase 3 the version.

The hooks:

- One `hooks/hooks.json` serves both hosts, named by neither manifest: both read that default path and give hook processes `CLAUDE_PLUGIN_ROOT`.
- A script in `hooks/`, standard-library Python like the CLI, reads either host's input and takes every fact from `pipeline.py`; it knows only which file of a plan is which. A second reader of the state is the drift GSD paid for.
- SessionStart on `startup|resume|compact` gives `status <plan>` for each plan that `status` with no plan lists, `building` to `passed`; with none, nothing. The full status, about 2 KB, holds the phases, the ready list and what is open; a one-line list only sends the agent to fetch it.
- PostToolUse after Claude Code's file-edit tools and Codex's `apply_patch` (which answers to the same matcher names; its paths come from the patch), on a plan whose `<slug>.json` exists: for the plan's `.md`, the drift lines `status <plan>` prints, each naming its fix; for `.notes.md`, that `note add|edit|drop` writes it and the next write replaces the edit; for `.judge.md`, that code writes it once from the first verdict; for `.json`, that the state changes only through `pipeline.py` commands. A draft without state, the run file and every other path get nothing: the plan text is the orchestrator's until `approve`.
- Both hooks hand their text to the model as `additionalContext`: Codex's `systemMessage` and Claude Code's plain PostToolUse output reach only the user.
- The hooks never block: no PreToolUse, no matcher on shell commands, no decision field, exit 0 always; their own failure (no repository, bad input, the CLI failing) prints nothing. Off, or untrusted in Codex, they change no run, so no skill or role file mentions them.
- In Codex every plugin update asks the user to trust the hooks again; untrusted, they stay silent. Accepted; README says so.

The docs:

- README's pipeline and roles, `references/VOCABULARY.md` and `docs/pipeline.html` describe 5.1: the run file before the plan (`dev-skills:run-file`, `<slug>.run.toml`); the CLI keeping the state and rendering the plan, notes, judge file and gate page; at the gate code runs the checks, records findings, results and verdicts, holds the caps, lands and finishes as the run file says; finish asks nothing. The vocabulary gains the run file and the CLI.
- README, the vocabulary and the drawing name no fix, round or stop count: caps live only in code (`build#caps-in-code`). TC-13's caps check widens to `README.md`, `references/` and `docs/`.
- README's "ships no hooks" becomes what the hooks say, how each host approves them (enabling the plugin; trust in Codex) and that untrusted hooks lose only the advice. TC-13 stops forbidding `hooks/` and pins the advisory shape. The marketplace description names the CLI, the run file and the hooks in place of "one script for the spec, no hooks".

The release: 5.1.0 in the four version lines `a0a41ac` changed, as the last phase, so it carries the whole epic.

## Out of scope

- A blocking hook, a guard reading shell commands, any hook event beyond the two.
- `pipeline.py`: the hooks use `status` as plans 1–4 left it; `.notes.md` and `.judge.md` keep their headers.
- `references/CODEX.md` and the skills: no step depends on a hook.
- Pushing, tagging and installing 5.1.0, and the live checks in both hosts: the owner's, after the merge.

## Done and Spec

```text
## Done

1. Run `scripts/check` and `scripts/test` → both exit 0; `hooks/hooks.json` declares only SessionStart on `startup|resume|compact` and PostToolUse on the edit tools; no line in `skills/`, `agents/`, `references/`, `AGENTS.md`, `README.md` or `docs/` caps fixes or judge rounds; the plugin's version lines agree.
2. A throwaway repo with plans `building`, `approved` and `merged`: Claude Code's SessionStart input with source `compact`, `resume` or `startup`, and Codex's with `compact` → `additionalContext` holding `status` of the building plan alone. With no plan from `building` to `passed` → nothing, exit 0.
3. The building plan: Claude Code's `Edit` input on its Status line → the advice names `pipeline.py plan status`; on a phase heading → `phase start / phase done`; on its Approach → `pipeline.py approve`. Codex's `apply_patch` input on its notes and judge files → a line each, naming `note add|edit|drop` and the first verdict. `Write` on its `<slug>.json` → the state changes only through `pipeline.py` commands.
4. An edit of a draft plan with no state, of a run file, or of `src/a.py` → nothing, exit 0.
5. Either hook's input outside a git repository, malformed JSON on stdin, or a corrupt `<slug>.json` → nothing on stdout, exit 0.
6. Read README, the vocabulary, `docs/pipeline.html` and the marketplace description → the run file before the plan, the CLI keeping the state, code running the gate's checks and caps, land and finish; finish asks nothing; README says what the hooks advise, how each host approves them, and that untrusted hooks lose only the advice; nothing says "no hooks" or "one script for the spec".
7. After the merge and an install in Claude Code, a plan building: start a session, `/compact`, resume → `status` of that plan in context each time; edit its Status line by hand → the advice names `pipeline.py plan status` — you check
8. In Codex after updating the plugin → it asks to trust the hooks; trusted → SessionStart hands over the building plan's `status`, and an `apply_patch` of its Status line draws the advice naming `pipeline.py plan status`; untrusted → no advice, and a run goes the same — you check

## Spec

+ hooks — Hooks
  About: The plugin's hooks in Claude Code and Codex, which hand agents what the CLI reports.
+ hooks#advise-only — The plugin's hooks only advise: none blocks a tool or reads a shell command, and one that fails prints nothing and exits 0
  Why: the CLI refuses broken input itself, Codex skips hooks not trusted again since an update, and a guard over commands grows without end
  Done: 1, 5, 8
+ hooks#status-at-start — When a session starts, resumes or is compacted, the agent gets `status` of each plan from `building` to `passed`, and nothing when there is none
  Why: a compaction drops the run's state from context, and the CLI holds it
  Done: 2, 7
+ hooks#edit-names-command — After an edit of a compiled plan's rendered or state file, the agent is told which `pipeline.py` command makes that change
  Why: a hand edit is drift that later writes refuse, or that the next render discards
  Done: 3, 4, 7
```
