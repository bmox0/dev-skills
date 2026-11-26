This is history; the rules that hold now are in `docs/spec/`.

# Plan: land, the human gate page and finish in code

## Result

Agents retype land's git, the gate page and finish every run; pages carried a stale item and a decided Open, and after land the records name commits only the backup holds. After this plan, `pipeline.py` lands the branch by the shape the agent writes, checks the tree against the backup and records the land. It renders the page from the records, flagging what was not taken on the tip's tree, and `finish` ends the run as the run file says, by forge for a merge request. The CLI's leftovers from plans 2–3 close with it.

## Approach

The epic's Interfaces and the Approaches of plans 1–3 are the contract. Phase 1 lands, phase 2 renders the page, phase 3 finishes, phase 4 closes the leftovers, phase 5 rewrites the prose.

Land:

- The judge still lands on a pass and writes the shape: a TOML file, read with `tomllib`, holding each commit's paths, message and walkthrough, and on a re-land the text on what changed since. `land draft` starts it: on a re-land the last shape, the paths it lacks listed apart; else one commit holding every path. One file makes the rewrite one command.
- Before touching git, `land` refuses a dirty tree, naming what is there, and a shape that leaves out or repeats a path of `<base>..HEAD`. Then it saves `backup/<branch>-<n>`, rewrites, and compares the tree with the backup's. 19 real lands ran this git alike, and with the shape checked first, a difference can only be a hook's.
- A differing tree stays rewritten, and `land` prints the difference and any stash a hook left. `land accept --note` keeps it, the note goes on the page, and the page says the tip is not the tree the checks passed. `land revert` resets to the backup and records a stop. No checks run.
- A land is recorded: backup, pre-land head, tip, shape. `status` names the tip, the head whose tree it has, and the backup holding the commits earlier records name. Land renders `### The commits · landed <tip> · backup/<branch>-<n>`: a line on the tree; on a re-land, `git range-diff <base> <last tip> <tip>` and the since text; each commit with its message and walkthrough; the fixes and rounds from their records.
- Land records each stop, a dirty tree or a revert, with its message; the count restarts after a land. Past code's cap, a stop is a question to the user with land's message, held as a `question` verdict is. The count leaves build's prose.
- `verdict evidence-owed` records who owes what, with no decisions; the next judge brief is the same case.

The page:

- Once a land is recorded, `## Human gate` is code's: every render redraws it from the records, and a hand edit is drift. A plan with no land record keeps its section as written.
- `page --note "<how to try it>" [--message "<…>"]` records the note and the merge message or request title, and sets `at the human gate`. It is refused before a land, and without a message when the run ends in `no-ff` or a merge request. The page names the ending, so the user's word at the gate approves it and finish asks nothing.
- Build's order stays, with the note and the ending first; Decided without you includes deviations' `--note`s, and Open holds what is undecided, let through, survived its fix or not reached, the last verdict's report without the Prediction, and any stop; an item a fix or round closed shows once, under that fix or round. Labels are code's, in English as in the notes file; every text keeps its author's words.
- A result, check run or verdict taken on a tree other than the tip's is flagged with its commit; one on the pre-land head is not. A record with no commit is flagged as unknown. Each flag names the paths changed between that tree and the tip's; whether a change touched a case stays the reader's call.

Finish:

- `finish` follows the approved `[finish]` and is refused unless the plan is `passed` or a request's link. A local merge runs in the clean tree that has the target checked out, else here after switching. A refused `--ff-only` or a conflict leaves everything as it was, the merge aborted, and says why. A merge sets `merged`, which the epic's row follows, and says nothing was pushed.
- A merge request goes by the forge the remote's URL names: GitHub, a push and `gh pr create` with the message as title and the page as body; GitLab, push options for create, target and title, which carry no line break, so no page (its one real request went this way); elsewhere nothing is pushed and the agent opens it. The printed link, or the agent's through `plan status`, becomes the Status. Later `finish` asks `gh pr view` on GitHub; elsewhere it takes `--merged` once the agent has seen it merged.
- Only the plan's branch is pushed, and only for a merge request: the run file holds the user's word for it.
- After the merge, local or a merged request: the worktree is removed, never forced, and the data directory too; backups, `backup/<branch>-` and digits only, are deleted when `delete_backups` is true, else listed; the branch stays.
- A conflict at finish is a round: `round start --conflict "<what>"` opens a cycle of its own with no notes and a fresh count. On that path `gate start` fed the gate's cycle while `fix start` read the newest.

Leftovers:

- The full checks run outside the plan lock, each result recorded as it ends. A run whose call is gone shows as unfinished and runs again; a command that needs it refuses meanwhile. They take about 3 minutes here, past a 2-minute shell timeout, and a killed call recorded nothing. Build's prose says these calls run long.
- The rest are fixes, as Done 15–17 state them.

## Out of scope

- Judgment: the commit shape, messages, walkthroughs, keeping a hook's change, whether a flagged result holds, the merge message, a conflict's resolution, the retro.
- Translated page labels; `glab` and forge APIs; squash merges; deleting the plan's branch.
- `README.md`, `references/VOCABULARY.md` and `docs/pipeline.html`, whose land and finish lines describe 5.0.

## Done and Spec

```text
## Done

1. Run `scripts/check` and `scripts/test` → both exit 0; no line in `skills/`, `agents/` or `AGENTS.md` counts land stops, and the land and finish skills run no `reset`, `commit`, `merge`, `push`, `gh` or `branch -D` themselves.
2. In a throwaway repo, a plan whose judge passed, a file uncommitted: `land` → refused, naming it. Moved away: `land draft` → one commit holding every changed path; a shape missing or repeating a path → refused, naming it. A two-commit shape → `backup/<branch>-1` at the old HEAD, two commits with their messages, `git diff backup/<branch>-1 HEAD` empty; `status` names the tip, the old HEAD as its tree and the backup; the plan holds `### The commits · landed <tip> · backup/<branch>-1` with each message, walkthrough and fix.
3. After a round commits a new file: `land draft` → the last shape with the new path apart, and `land` refuses until it is placed. Landed → `backup/<branch>-2`, and one commits section with `git range-diff <base> <last tip> <tip>` and the since text.
4. A pre-commit hook reformats a file: `land` → the rewrite stays, the difference printed; `land revert` → the branch is the backup, a stop recorded. Again with `land accept --note "<…>"` → the page shows the note and says the tip is not the tree the checks passed. A hook that leaves a stash → `land` names it.
5. Stop `land` on a dirty tree repeatedly → the stop past code's cap is a question: `status` shows land's message, and `brief judge` refuses without `--note` holding the answer.
6. `verdict evidence-owed --owed verify --report "<…>"` with an Open entry undecided → recorded, listed by `status`; the next `brief judge` is the same case.
7. After a land, on a plan ending `no-ff`: `page --note "<…>"` without `--message` → refused; with one → Status `at the human gate`, and `## Human gate` holds in order the note, ending and message; Decided without you with costs; Open with each verdict and its decisions, no Prediction, a survivor, a case not reached with its need, an Observation; E2E with the level, the raising path, each Done case's result and commit, `you check` last; the commits. Before a land → refused.
8. A result taken before a later fix → flagged with its commit; one on the pre-land head → not flagged; one with no commit → flagged as unknown. A hand edit to the page → drift. A hand-written `## Human gate` with no land → byte for byte after `plan status`.
9. `finish`, `ff-only` into `main`, backups kept: at `at the human gate` → refused. At `passed` → `main` at the tip, Status and the epic's row `merged`, the branch and both backups kept, "nothing pushed". With `main` moved on → refused, Status `passed`, nothing changed.
10. `finish`, `no-ff`, `delete_backups = true`, with a worktree and a data directory → a merge commit with the page's message; `backup/<branch>-1` and `-2` gone, `backup/<branch>-old` and other branches' backups kept; worktree and data directory removed, branch kept. A conflicting `main` → merge aborted, tree clean, Status `passed`, the conflicting paths printed.
11. A merge request, the remote's URL on `github.com`, a stand-in `gh` → the branch pushed, `gh pr create` with the base, the message as title and the page as body, Status the printed link, `main` untouched. `finish` again: `gh` says merged → `merged`; open → it says so, nothing changes.
12. The remote on a GitLab host → one push with the create, target and title options, and its printed link is the Status. An unknown host → nothing pushed, and it says to open the request and record its link; then `finish --merged` → `merged`.
13. At finish, `round start --conflict "<…>"` → a round with no notes; after its commit, `round done` checks in the round's cycle, and `fix start` takes that cycle's red check, not the gate's.
14. A `full` command that sleeps; kill `gate start` mid-run → meanwhile `note add` succeeds; `status` shows the run unfinished; the next `gate start` runs it again.
15. A plan with no run values: `gate start` → refused, nothing committed.
16. Two `verdict round` with no round between → `round start` takes both verdicts' notes. `round report` without `--commit` → recorded; `brief reviewer` says the round made no commit. At the gate before a fix, `brief verify --cases 2` twice → two files, the first unchanged.
17. Two `build start` at once, each with a port → different ports. `port` turned on for a `merged` plan, `approve` → nothing allocated. `pipeline.py`'s docstring → names every command `--help` lists.
18. In a throwaway repo, run `dev-skills:build` from this checkout on a two-phase plan ending `ff-only`, through `dev-skills:finish` → the judge lands through `CLI land`, the page comes from `CLI page`, finish merges through `CLI finish` without asking how, and no one writes the page or runs land's or finish's git by hand — you check
19. After a land, a file uncommitted: `land revert` → refused, naming it; the branch, the backup and the file unchanged.
20. After a land and `page`, `land revert` until no land is left → the page record is gone; at `passed`, `finish` ending `ff-only` or `no-ff` → refused `no-land`, nothing merged, the target unmoved.
21. A request opened on GitHub, Status the link: `finish` → asks `gh pr view`, no `page-differs`; on an unknown host, a recorded link and `finish --merged` → `merged`. A GitLab push that prints no link → it says the request was pushed; `finish` again → nothing pushed, it says to record the link with `plan status`.
22. A conflict round → `brief round` and `brief judge` carry the conflict text; `status` prints the round's line whole; a round with no commit renders whole in the commits section. `finish` with a target other than `main` → its lines name that target. `pipeline.py status /nonexistent/x.md` → one refusal line, exit 1, no traceback.
23. A gate whose Conventions a round closed, then a pass → `### Open` holds only what is undecided, let through, survived its fix or not reached, and the last verdict's report; each closed item shows once, under the fix or round that closed it; no verdict's decisions repeat as findings; `status` marks each finding with the cycle that closed it. A flagged result names the paths changed between its tree and the tip's.
24. `brief reviewer` says to record an unjudged item only when there is one; `brief phase`, `brief fix` and `brief round` say, beside the plan's Spec entries, that each test guarding one carries its ID. `fix start` with nothing open → a fix line that fits an empty list. gate.md skips `fix start` with nothing open and dispatches no verify worker when `brief verify` has no case, and the judge brief says so. Build's prose says what a killed check call leaves.

## Spec

+ land — Land
  About: Rewriting a plan's branch into the commits a reviewer reads, before the human gate.
+ land#backup-first — Land and its revert refuse a dirty tree, and land keeps the branch as `backup/<branch>-<n>` before it rewrites it
  Why: uncommitted files are someone's, and the backup holds the commits the gate's records name
  Done: 2, 19
+ land#checked-tree — The landed tip has the tree the checks passed, unless the agent keeps a hook's change with a note the gate page shows
  Why: the checks vouch for one tree, and a formatter hook once changed it at commit
  Done: 2, 4
+ land#recorded — After land, `status` and the gate page name the landed tip, the head whose tree it has, and the backup holding the earlier commits
  Why: after a land every record named commits only the backup held, and the tip appeared nowhere
  Done: 2
+ land#stops-to-user — Past code's cap, a land stop goes to the user as a question with land's message, and no judge runs until they answer
  Why: a land that stops on the same input stops again, and the count stays out of prose an agent reads
  Done: 1, 5
+ build#page-from-records — The human gate page is rendered from the records; Open holds only what is still open, and each result, check run and verdict not taken on the tip's tree is flagged with the paths changed since
  Why: hand-written pages carried a stale item and an Open already decided
  Done: 7, 8, 23
~ finish#backups-delete-asks — After the merge, the plan's backups are deleted only when the run file says so; the plan's branch is the user's
  Why: the user answers once, before the plan, and a branch is the user's to remove
  Done: 9, 10
+ finish#by-run-file — Finish ends the run as the run file's `[finish]` says; at the gate it needs only the user's word
  Why: how a run ends is asked once, before the plan, so nothing pulls the user in at the end
  Done: 9, 10, 18
+ finish#request-by-forge — A merge request goes through the forge the remote's URL names: `gh` for GitHub, push options for GitLab; on any other host the agent opens it
  Why: the one real GitLab request went through push options, not `gh`
  Done: 11, 12, 21
+ finish#push-only-for-request — Finish pushes only the plan's branch, and only when the run ends in a merge request
  Why: a push leaves the machine, and the run file's merge request is the user's word for it
  Done: 9, 11, 12, 21
+ finish#merge-needs-land — Finish merges or opens a request only for a landed branch, and a revert to no land clears the page
  Why: the page the user approves is drawn from the land; after a revert there is nothing approved to merge
  Done: 20
```
