# Worktrees and workflow paths

- Start with `runweld task start ID --goal TEXT` before discovery.
  Add `--bug` when a red reproduction is required.
  Use its branch, base, tree, plan path and artifacts directory as printed.
  Repeating the ID keeps its tree, dated plan directory and run settings.
  Use `runweld next [ID]`, omitting the ID inside its worktree.
- Read and modify project source, including specs and project instructions,
  from the task tree. Run approval and report commands against the absolute
  plan path. Keep summaries, shape files and handoffs beside the plan in
  `.runweld/workflow/plans/YYYY-MM-DD-ID/`.
- Put task scratch files, captures, reproductions and prototypes under
  `runweld task path ID [CATEGORY]`. For project-wide epic, handoff, spec scratch
  or retro material use `runweld path epics`, `runweld path handoff`, `runweld path spec` or
  `runweld path retro`. These commands print paths without creating them; create
  the directory when writing. Put lasting rules in the tracked project.
- The first implementation phase or full check prepares the approved
  environment. `runweld task setup PLAN --preview` shows the command,
  checkout and resources without running it. Run without `--preview` to
  prepare or retry. For an active pre-plan bug reproduction, add
  `--reproduction` to both commands. Reuse the worktree and allocated resources.
  `[setup].command` runs in the task worktree and receives
  `RUNWELD_SOURCE_CHECKOUT`, `RUNWELD_TASK_PATH`, `RUNWELD_PLAN`,
  `RUNWELD_WORKFLOW`, `RUNWELD_ARTIFACTS` and any allocated
  `RUNWELD_PORT` or `RUNWELD_DATA_DIR`. Use these locations to keep the
  checkout clean. A successful setup is reused for the same inputs.
- Finish keeps private history. If integration succeeds and cleanup refuses a
  worktree with unsaved or ignored local files, keep those files or move them
  out, then rerun `runweld finish PLAN` for cleanup alone.
