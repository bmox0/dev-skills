# Hooks

The plugin's hooks in Claude Code and Codex, which hand agents what the CLI reports.

### advise-only — Host hooks are optional advice: they neither block tools nor replace mandatory CLI checks or approval safeguards, and handler failures print nothing and exit 0

Why: workflow correctness must survive absent or unusable hook integration

- Drive normalized advice and native hook fixtures, including Qoder-only plugin root → intended status/edit advice; malformed/unrelated input is quiet; disabled hooks skip no CLI safeguard.
- Complete consent → build → gate/judge → land → page → acceptance → configured finish without hooks → existing safeguards, reasoned dispositions, hook exceptions and cleanup remain correct.

### status-at-start — Supported native lifecycle events deliver the CLI's active-plan status through the common advisory handler

Why: adapters translate delivery while the CLI remains the state source

- Drive normalized advice and native hook fixtures, including Qoder-only plugin root → intended status/edit advice; malformed/unrelated input is quiet; disabled hooks skip no CLI safeguard.

### edit-names-command — Supported native edit events advise which CLI command changes a compiled plan file; unrelated edits add no advice

Why: native payloads must preserve the shared state-editing contract

- Drive normalized advice and native hook fixtures, including Qoder-only plugin root → intended status/edit advice; malformed/unrelated input is quiet; disabled hooks skip no CLI safeguard.
