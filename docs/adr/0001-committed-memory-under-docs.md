# Committed memory under docs/, ephemeral artifacts under .ai-workflow/

The pipeline is growing a memory that outlives runs — the glossary
(`CONTEXT.md`), ADRs, unpaid debt (`DEBT.md`), and distilled lessons
(`LESSONS.md`). Memory in a gitignored directory does not survive a fresh
clone and is invisible to anyone browsing the repository, so everything
persistent lives in `docs/` and is committed; everything that dies with a run
— plans, epics, briefs, reports, evidence, prototypes, handoffs — and the
machine-written run records (`runs.tsv`) stay in the gitignored
`.ai-workflow/`. Nothing keeps backward compatibility with the old root
locations (`CONTEXT.md` at the repository root); this plugin has a single
user, and a migration shim would outlive its usefulness.

## Considered Options

- Persistent files at the repository root (`CONTEXT.md` beside the code) —
  rejected: scatters memory across the tree instead of one directory.
- All pipeline memory in `.ai-workflow/` — rejected: gitignored memory is not
  memory; it dies with the checkout and never appears in history.

## Consequences

- Pipeline memory leaves a visible trace in every clone and every diff that
  touches it; that visibility is the point.
- `branch-guard`'s allowance moves from root `CONTEXT.md` to `docs/` as a
  whole.
- `runs.tsv` deliberately stays machine-side: its reader is the calibration
  route, not a person, and its rows belong beside the run artifacts they
  describe.
