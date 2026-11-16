# Hooks

The plugin's hooks in Claude Code and Codex, which hand agents what the CLI reports.

### advise-only — The plugin's hooks only advise: none blocks a tool or reads a shell command, and one that fails prints nothing and exits 0

Why: the CLI refuses broken input itself, Codex skips hooks not trusted again since an update, and a guard over commands grows without end

- Run `scripts/check` and `scripts/test` → both exit 0; `hooks/hooks.json` declares only SessionStart on `startup|resume|compact` and PostToolUse on the edit tools; no line in `skills/`, `agents/`, `references/`, `AGENTS.md`, `README.md` or `docs/` caps fixes or judge rounds; the plugin's version lines agree.
- Either hook's input outside a git repository, malformed JSON on stdin, or a corrupt `<slug>.json` → nothing on stdout, exit 0.
- In Codex after updating the plugin → it asks to trust the hooks; trusted → SessionStart hands over the building plan's `status`, and an `apply_patch` of its Status line draws the advice naming `pipeline.py plan status`; untrusted → no advice, and a run goes the same

### status-at-start — When a session starts, resumes or is compacted, the agent gets `status` of each plan from `building` to `passed`, and nothing when there is none

Why: a compaction drops the run's state from context, and the CLI holds it

- A throwaway repo with plans `building`, `approved` and `merged`: Claude Code's SessionStart input with source `compact`, `resume` or `startup`, and Codex's with `compact` → `additionalContext` holding `status` of the building plan alone. With no plan from `building` to `passed` → nothing, exit 0.
- After the merge and an install in Claude Code, a plan building: start a session, `/compact`, resume → `status` of that plan in context each time; edit its Status line by hand → the advice names `pipeline.py plan status`

### edit-names-command — After an edit of a compiled plan's rendered or state file, the agent is told which `pipeline.py` command makes that change

Why: a hand edit is drift that later writes refuse, or that the next render discards

- The building plan: Claude Code's `Edit` input on its Status line → the advice names `pipeline.py plan status`; on a phase heading → `phase start / phase done`; on its Approach → `pipeline.py approve`. Codex's `apply_patch` input on its notes and judge files → a line each, naming `note add|edit|drop` and the first verdict. `Write` on its `<slug>.json` → the state changes only through `pipeline.py` commands.
- An edit of a draft plan with no state, of a run file, or of `src/a.py` → nothing, exit 0.
- After the merge and an install in Claude Code, a plan building: start a session, `/compact`, resume → `status` of that plan in context each time; edit its Status line by hand → the advice names `pipeline.py plan status`
