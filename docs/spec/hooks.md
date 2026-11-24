# Hooks

The plugin's hooks in Claude Code and Codex, which hand agents what the CLI reports.

### advise-only — Host hooks are optional advice: they neither block tools nor replace mandatory CLI checks or approval safeguards, and handler failures print nothing and exit 0

Why: workflow correctness must survive absent or unusable hook integration

- Drive normalized advice and native hook fixtures, including Qoder-only plugin root → intended status/edit advice; malformed/unrelated input is quiet; disabled hooks skip no CLI safeguard.
- Complete consent → build → gate/judge → land → page → acceptance → configured finish without hooks → existing safeguards, reasoned dispositions, hook exceptions and cleanup remain correct.

### status-at-start — Supported lifecycle hooks deliver current CLI progress for relevant plans across linked worktrees

Why: a resumed agent needs the same plan and next action it would find from the main checkout

- Resume an approved plan and a building plan from their relevant checkouts → CLI and hook agree on the plan, stage, owner and next action. With several plans each has its own path. A session unrelated to any run gets no unsolicited workflow.

### edit-names-command — Supported native edit events advise which CLI command changes a compiled plan file; unrelated edits add no advice

Why: native payloads must preserve the shared state-editing contract

- Drive normalized advice and native hook fixtures, including Qoder-only plugin root → intended status/edit advice; malformed/unrelated input is quiet; disabled hooks skip no CLI safeguard.
