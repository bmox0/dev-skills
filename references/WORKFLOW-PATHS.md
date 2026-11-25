# Worktrees and workflow paths

## Installed ds

- Start new work with `ds task start ID` before grill, reproduction or planning.
  Use its branch, base, tree, plan path and artifacts directory as printed.
  Repeating the ID keeps its tree and run settings. From a fresh tab use
  `ds task resume ID` or `ds status --current`.
- Read and modify project source, including specs and project instructions,
  from the task tree. Run approval and report commands against the absolute
  plan path. Keep summaries, shape files and handoffs beside the plan.
- Put task scratch files, captures, reproductions and prototypes under
  `ds task path ID [CATEGORY]`. For project-wide epic, handoff, spec scratch
  or retro material use `ds path epics`, `ds path handoff`, `ds path spec` or
  `ds path retro`. These commands print paths without creating them; create
  the directory when writing. Put lasting rules in the tracked project.
- Plan before preparing a runtime. The first implementation phase or full
  check prepares the approved environment. Run `ds task setup PLAN` after
  run and summary approval if the environment is needed sooner or setup
  needs a retry. Use the printed worktree and allocated resources again.
- Finish keeps private history. If integration succeeds and cleanup refuses a
  worktree with unsaved or ignored local files, keep those files or move them
  out, then rerun `ds finish PLAN` for cleanup alone.

## Legacy plugin runs

Keep using the assigned checkout, CLI and absolute plan path. Keep new
artifacts beside the run or under its checkout's ignored `.ai-workflow/`.

`ds init` exposes legacy history in `.ds/workflow/legacy/`. Main checkout
history stays put. Linked history moves to the archive, with a link at the old
path so existing commands and locks keep working. Removing a linked checkout
keeps its archive in `ds status`. Move collisions aside and retry. Unversioned
runs stay unversioned.
