# Finish

Merging a plan's branch at the end of the pipeline, and what is left behind.

### backups-delete-asks — After the merge the plan's backups are deleted only on the user's yes; the plan's branch is the user's

Why: a backup is a copy someone may still want, and a branch is the user's to remove

- In a throwaway repo, a plan at `passed` on branch `feat/x` with `backup/feat/x-1` and `backup/feat/x-2`. Run `dev-skills:finish`, choose `--ff-only`, answer no to the backup question → the merge is in, `feat/x` and both backups remain.
- The same setup, answer yes → `git branch --list 'backup/feat/x-*'` is empty, `feat/x` remains, and the retro is offered after.
