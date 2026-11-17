# Finish

Merging a plan's branch at the end of the pipeline, and what is left behind.

### backups-delete-asks — After the merge, the plan's backups are deleted only when the run file says so; the plan's branch is the user's

Why: the user answers once, before the plan, and a branch is the user's to remove

- `finish`, `ff-only` into `main`, backups kept: at `at the human gate` → refused. At `passed` → `main` at the tip, Status and the epic's row `merged`, the branch and both backups kept, "nothing pushed". With `main` moved on → refused, Status `passed`, nothing changed.
- `finish`, `no-ff`, `delete_backups = true`, with a worktree and a data directory → a merge commit with the page's message; `backup/<branch>-1` and `-2` gone, `backup/<branch>-old` and other branches' backups kept; worktree and data directory removed, branch kept. A conflicting `main` → merge aborted, tree clean, Status `passed`, the conflicting paths printed.

### by-run-file — Finish uses the approved run ending after current authorized acceptance, without asking the ending again

Why: configuration is agreed during planning and execution requires current acceptance

- Complete phases, gate, judge, land, page and authorized acceptance, including a feedback round → ff-only finish uses the agreed ending and retains backups; existing judge dispositions and explicit land-hook exceptions remain visible and supported.

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

### merge-needs-land — Finish independently verifies current judge, land, page and authorized acceptance before merging, pushing or opening a request

Why: a passed status alone cannot authorize an unreviewed result

- Attempt passed, request-link or merged shortcuts without required current judge, land, page or acceptance records → refused without state or target changes; supported request-link recording still works after a valid finish flow.
- Complete phases, gate, judge, land, page and authorized acceptance, including a feedback round → ff-only finish uses the agreed ending and retains backups; existing judge dispositions and explicit land-hook exceptions remain visible and supported.
- Change the branch tree or approved planning content after a page/acceptance → stale stages are identified; passed and finish refuse until the required evidence and acceptance are current.
