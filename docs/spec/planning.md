# Planning

Interviewing, configuring a run and approving its execution summary.

### summary-before-build — A human approves the displayed complete plan and configuration together before a separate build start

Why: one decision covers the exact work and execution terms presented together

- Review a complete plan and its config, approve once, then start separately. Change a criterion or finish target and see the affected approval become stale. Repeated start preserves the phase, worktree and executor.

### early-progress — Explicit stage entry, completion and optional skips preserve decisions across sessions

Why: a coordinator can recover the current work before a plan exists

- Resume an interrupted interview with its saved decisions. Exercise taking and skipping optional stages and refusing a required skip. For a bug reproduce it in a fresh tree and validate the plan against its actual base.
