# Finish

Merging a plan's branch at the end of the pipeline, and what is left behind.

### backups-delete-asks — After the merge, the plan's backups are deleted only when the run file says so; the plan's branch is the user's

Why: the user answers once, before the plan, and a branch is the user's to remove

- `finish`, `ff-only` into `main`, backups kept: at `at the human gate` → refused. At `passed` → `main` at the tip, Status and the epic's row `merged`, the branch and both backups kept, "nothing pushed". With `main` moved on → refused, Status `passed`, nothing changed.
- `finish`, `no-ff`, `delete_backups = true`, with a worktree and a data directory → a merge commit with the page's message; `backup/<branch>-1` and `-2` gone, `backup/<branch>-old` and other branches' backups kept; worktree and data directory removed, branch kept. A conflicting `main` → merge aborted, tree clean, Status `passed`, the conflicting paths printed.

### by-run-file — Finish ends the run as the run file's `[finish]` says; at the gate it needs only the user's word

Why: how a run ends is asked once, before the plan, so nothing pulls the user in at the end

- `finish`, `ff-only` into `main`, backups kept: at `at the human gate` → refused. At `passed` → `main` at the tip, Status and the epic's row `merged`, the branch and both backups kept, "nothing pushed". With `main` moved on → refused, Status `passed`, nothing changed.
- `finish`, `no-ff`, `delete_backups = true`, with a worktree and a data directory → a merge commit with the page's message; `backup/<branch>-1` and `-2` gone, `backup/<branch>-old` and other branches' backups kept; worktree and data directory removed, branch kept. A conflicting `main` → merge aborted, tree clean, Status `passed`, the conflicting paths printed.
- In a throwaway repo, run `dev-skills:build` from this checkout on a two-phase plan ending `ff-only`, through `dev-skills:finish` → the judge lands through `CLI land`, the page comes from `CLI page`, finish merges through `CLI finish` without asking how, and no one writes the page or runs land's or finish's git by hand

### request-by-forge — A merge request goes through the forge the remote's URL names: `gh` for GitHub, push options for GitLab; on any other host the agent opens it

Why: the one real GitLab request went through push options, not `gh`

- A merge request, the remote's URL on `github.com`, a stand-in `gh` → the branch pushed, `gh pr create` with the base, the message as title and the page as body, Status the printed link, `main` untouched. `finish` again: `gh` says merged → `merged`; open → it says so, nothing changes.
- The remote on a GitLab host → one push with the create, target and title options, and its printed link is the Status. An unknown host → nothing pushed, and it says to open the request and record its link; then `finish --merged` → `merged`.
- A request opened on GitHub, Status the link: `finish` → asks `gh pr view`, no `page-differs`; on an unknown host, a recorded link and `finish --merged` → `merged`. A GitLab push that prints no link → it says the request was pushed; `finish` again → nothing pushed, it says to record the link with `plan status`.

### push-only-for-request — Finish pushes only the plan's branch, and only when the run ends in a merge request

Why: a push leaves the machine, and the run file's merge request is the user's word for it

- `finish`, `ff-only` into `main`, backups kept: at `at the human gate` → refused. At `passed` → `main` at the tip, Status and the epic's row `merged`, the branch and both backups kept, "nothing pushed". With `main` moved on → refused, Status `passed`, nothing changed.
- A merge request, the remote's URL on `github.com`, a stand-in `gh` → the branch pushed, `gh pr create` with the base, the message as title and the page as body, Status the printed link, `main` untouched. `finish` again: `gh` says merged → `merged`; open → it says so, nothing changes.
- The remote on a GitLab host → one push with the create, target and title options, and its printed link is the Status. An unknown host → nothing pushed, and it says to open the request and record its link; then `finish --merged` → `merged`.
- A request opened on GitHub, Status the link: `finish` → asks `gh pr view`, no `page-differs`; on an unknown host, a recorded link and `finish --merged` → `merged`. A GitLab push that prints no link → it says the request was pushed; `finish` again → nothing pushed, it says to record the link with `plan status`.

### merge-needs-land — Finish merges or opens a request only for a landed branch, and a revert to no land clears the page

Why: the page the user approves is drawn from the land; after a revert there is nothing approved to merge

- After a land and `page`, `land revert` until no land is left → the page record is gone; at `passed`, `finish` ending `ff-only` or `no-ff` → refused `no-land`, nothing merged, the target unmoved.
