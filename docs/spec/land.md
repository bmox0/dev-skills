# Land

Rewriting a plan's branch into the commits a reviewer reads, before the human gate.

### backup-first — Land and its revert refuse a dirty tree, and land keeps the branch as `backup/<branch>-<n>` before it rewrites it

Why: uncommitted files are someone's, and the backup holds the commits the gate's records name

- In a throwaway repo, a plan whose judge passed, a file uncommitted: `land` → refused, naming it. Moved away: `land draft` → one commit holding every changed path; a shape missing or repeating a path → refused, naming it. A two-commit shape → `backup/<branch>-1` at the old HEAD, two commits with their messages, `git diff backup/<branch>-1 HEAD` empty; `status` names the tip, the old HEAD as its tree and the backup; the plan holds `### The commits · landed <tip> · backup/<branch>-1` with each message, walkthrough and fix.
- After a land, a file uncommitted: `land revert` → refused, naming it; the branch, the backup and the file unchanged.

### checked-tree — The landed tip has the tree the checks passed, unless the agent keeps a hook's change with a note the gate page shows

Why: the checks vouch for one tree, and a formatter hook once changed it at commit

- In a throwaway repo, a plan whose judge passed, a file uncommitted: `land` → refused, naming it. Moved away: `land draft` → one commit holding every changed path; a shape missing or repeating a path → refused, naming it. A two-commit shape → `backup/<branch>-1` at the old HEAD, two commits with their messages, `git diff backup/<branch>-1 HEAD` empty; `status` names the tip, the old HEAD as its tree and the backup; the plan holds `### The commits · landed <tip> · backup/<branch>-1` with each message, walkthrough and fix.
- A pre-commit hook reformats a file: `land` → the rewrite stays, the difference printed; `land revert` → the branch is the backup, a stop recorded. Again with `land accept --note "<…>"` → the page shows the note and says the tip is not the tree the checks passed. A hook that leaves a stash → `land` names it.

### recorded — After land, `status` and the gate page name the landed tip, the head whose tree it has, and the backup holding the earlier commits

Why: after a land every record named commits only the backup held, and the tip appeared nowhere

- In a throwaway repo, a plan whose judge passed, a file uncommitted: `land` → refused, naming it. Moved away: `land draft` → one commit holding every changed path; a shape missing or repeating a path → refused, naming it. A two-commit shape → `backup/<branch>-1` at the old HEAD, two commits with their messages, `git diff backup/<branch>-1 HEAD` empty; `status` names the tip, the old HEAD as its tree and the backup; the plan holds `### The commits · landed <tip> · backup/<branch>-1` with each message, walkthrough and fix.

### stops-to-user — Past code's cap, a land stop goes to the user as a question with land's message, and no judge runs until they answer

Why: a land that stops on the same input stops again, and the count stays out of prose an agent reads

- Run `scripts/check` and `scripts/test` → both exit 0; no line in `skills/`, `agents/` or `AGENTS.md` counts land stops, and the land and finish skills run no `reset`, `commit`, `merge`, `push`, `gh` or `branch -D` themselves.
- Stop `land` on a dirty tree repeatedly → the stop past code's cap is a question: `status` shows land's message, and `brief judge` refuses without `--note` holding the answer.
