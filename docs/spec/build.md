# Build

Building an approved plan: its phases, the E2E gate, the judge and the rounds, up to the human gate.

### judge-after-every-round — Every round ends with the judge, on Opus, before the branch is landed and shown

Why: only the judge decides whether a round left anything, and weaker models judged worse in earlier versions

- The same plan after the round: the note has its commit and the targeted re-check is green. Run the judge → it reads the judge file, the round's notes and the re-check's results, but not the plan's other Done results or captures. It returns `pass:` after `land`, and the judge file is unchanged.
- The same plan at the human gate, after a round on one user note → the judge after it reads that note and the round's re-check, then lands.

### judge-reads-the-round — After a round the judge reads only what the round was for and the re-check's results

Why: what the round did not touch should not have changed, and the re-check, not the judge, finds regressions

- The same plan after the round: the note has its commit and the targeted re-check is green. Run the judge → it reads the judge file, the round's notes and the re-check's results, but not the plan's other Done results or captures. It returns `pass:` after `land`, and the judge file is unchanged.
- The same plan at the human gate, after a round on one user note → the judge after it reads that note and the round's re-check, then lands.

### state-through-commands — After approval a plan's state changes only through the CLI, and a write refuses while the plan file differs from its last render

Why: one writer per fact; a hand edit would vanish at the next render

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.
- Edit the Status line by hand, then run `phase start 1` → refused, naming the line and its command, and `status` still prints, showing the drift. Instead, edit a Done item and run `approve` → the plan is recompiled and every status is kept.

### act-with-a-reason — An agent may act against a fact the CLI reports, with a reason the CLI records for the human gate

Why: code states facts, agents keep the judgment

- Phase 1 commits one path inside its territory and one outside, leaves one staged, and records its report. `phase done 1` → exit 1, naming both, and the phase stays `in progress`. Grant the outside path, commit the staged one and record the report again → `phase done 1` marks it `done` and prints phase 2 as ready.
- Run `phase start 3` before phase 2 is done → refused; with `--note` → started, and `status` shows the note. Run `phase start 1` on the done phase with a note → back to `in progress`, with the note and HEAD's SHA.

### phase-done-checked — A phase is done once its reported commits are on the branch, inside its territory or grants, with nothing of its territory left uncommitted or staged

Why: the check sits in the command the orchestrator calls anyway

- Phase 1 commits one path inside its territory and one outside, leaves one staged, and records its report. `phase done 1` → exit 1, naming both, and the phase stays `in progress`. Grant the outside path, commit the staged one and record the report again → `phase done 1` marks it `done` and prints phase 2 as ready.

### base-is-named — The base is the ref the orchestrator names; the CLI never picks one

Why: in real runs the base is almost never the default branch

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.

### epic-row-follows — Under an epic, the plan's row shows the plan's status after every change

Why: the row was forgotten in 3 of 5 runs

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.

### pre-5-1-adopted — A plan without state is adopted by `approve` as its file stands; no other command but `spec` and `run` runs on it

Why: no migration step to remember, and a plan mid-build goes on where it is; the run file is written and checked before the plan has state

- Take a pre-5.1 plan at `building` with phase 1 `done` and no JSON, and run `phase start 2` → refused, with a fix naming `approve`. Run `approve` → phase 1 is still `done`, and phase 2 is ready.

### brief-carries-spec — An implementer's brief lists every `## Spec` entry of the plan with its ID and Done items

Why: tests carry the rule's ID, which lives only in the plan until `spec write`; a run lost a judge round to it

- Run `brief implementer 2` on a plan with three `## Spec` entries → the file holds `[checks].phase`, every `[run]` key as written with the keychain pointer unresolved, each entry's ID, statement and Done items, and one `Territory:` line.

### checks-by-code — The full checks run in code at the gate and at every re-check, whenever HEAD or the approved checks are new

Why: a round that skipped them reported a red word budget as green

- In a throwaway repo, a `small` plan with every phase done changes one path outside its territories and one under `docs/spec/`. Its `full` holds a passing command, a failing one and one that edits a tracked file. `gate start` → `docs/spec/` is committed alone; the level is `normal`, naming only the outside path; each command shows its exit code, the failing one its output tail, and the editing one is red. Again with no new commit → nothing runs, and the last result prints with its SHA; after a commit → they run.

### level-from-diff — The gate's level is the plan's, raised to normal by any changed path outside the plan's territories other than `docs/spec/`

Why: the level follows from the diff; a slip in this rule once shipped untested

- In a throwaway repo, a `small` plan with every phase done changes one path outside its territories and one under `docs/spec/`. Its `full` holds a passing command, a failing one and one that edits a tracked file. `gate start` → `docs/spec/` is committed alone; the level is `normal`, naming only the outside path; each command shows its exit code, the failing one its output tail, and the editing one is red. Again with no new commit → nothing runs, and the last result prints with its SHA; after a commit → they run.

### findings-recorded — With a plan, the reviewer and the e2e worker record each finding and result through the CLI, and every reader sees them from there

Why: free-text returns drifted in shape, so readers parsed them by guess

- At the gate, record two Defects, a Convention, an Observation and what could not be judged; then Done 1 passed, Done 2 failed, and Done 3 not reached with its need → `status` prints the three lists as review returns them and one line per case as verify does. The one list holds the red check, both Defects and Done 2, nothing else. A result without a capture → refused.

### survivor-to-open — A fix takes every open item of the one list; an item found again after its fix goes to Open and gets no second fix

Why: a second try at the same finding repeats the first; the judge or the user decides it

- `fix start` takes the one list, and `brief fix` holds each item's `file:line` and text. After its commit and report, `fix done` → the full checks run at the new HEAD. Record Done 2 failed again, the first Defect as one the fix took, and a new Defect → the first two go to Open, and the next fix takes only the new one. At code's cap, `fix start` → refused. `status` shows each fix with its items and commits.

### caps-in-code — Code alone caps fixes per check cycle and judge rounds per gate, and stops rounds that stop converging; no cap or threshold appears in prose an agent reads

Why: a number in prose becomes a quota

- Run `scripts/check` and `scripts/test` → both exit 0, and no line in `skills/`, `agents/` or `AGENTS.md` says how many fixes or judge rounds are allowed, or when rounds stop.
- `fix start` takes the one list, and `brief fix` holds each item's `file:line` and text. After its commit and report, `fix done` → the full checks run at the new HEAD. Record Done 2 failed again, the first Defect as one the fix took, and a new Defect → the first two go to Open, and the next fix takes only the new one. At code's cap, `fix start` → refused. `status` shows each fix with its items and commits.
- Order judge rounds in one gate → the one past code's cap is stopped: no round opens, and `status` shows the reason. In fresh gates, each sign stops a `verdict round` with its reason: rounds that leave no fewer new notes than they took, until code stops them; a check red, green after a fix, then red again; a cycle's fixes spent with a Defect standing. After a user's round at the human gate, the count starts afresh.

### judge-file-by-code — `<slug>.judge.md` is written once, by code, from the first verdict, with HEAD, a UTC time and the engine

Why: written by hand, its format drifted: time zones, a slug without its date

- `verdict pass` with a decision for each Open entry and Convention and a Prediction → `.judge.md` names the slug, HEAD's SHA, a UTC time ending in `Z` and the engine; a later verdict leaves it byte for byte. A verdict leaving one undecided → refused, naming it.

### notes-in-their-words — Each note keeps its author's words, the user's or the judge's, and code alone numbers notes and rounds

Why: the round's implementer reads the note as it was said

- Record three user notes and mark one `task` → `<slug>.notes.md` lists two under Open and one under Tasks, in the words given, with their causes. `round start` takes the two; after one commit, `round done` → the heading reads ``## Round 1 · `<sha>` ``, and after two commits, `<first>..<last>`. `verdict round` → its notes are recorded with source `judge`, in the judge's words.

### page-from-records — The human gate page is rendered from the records; Open holds only what is still open, and each result, check run and verdict not taken on the tip's tree is flagged with the paths changed since

Why: hand-written pages carried a stale item and an Open already decided

- After a land, on a plan ending `no-ff`: `page --note "<…>"` without `--message` → refused; with one → Status `at the human gate`, and `## Human gate` holds in order the note, ending and message; Decided without you with costs; Open with each verdict and its decisions, no Prediction, a survivor, a case not reached with its need, an Observation; E2E with the level, the raising path, each Done case's result and commit, `you check` last; the commits. Before a land → refused.
- A result taken before a later fix → flagged with its commit; one on the pre-land head → not flagged; one with no commit → flagged as unknown. A hand edit to the page → drift. A hand-written `## Human gate` with no land → byte for byte after `plan status`.
- A gate whose Conventions a round closed, then a pass → `### Open` holds only what is undecided, let through, survived its fix or not reached, and the last verdict's report; each closed item shows once, under the fix or round that closed it; no verdict's decisions repeat as findings; `status` marks each finding with the cycle that closed it. A flagged result names the paths changed between its tree and the tip's.

### separate-build-session — On the user's start instruction, the original session launches build in a new herdr tab in the same workspace and remains the user's orchestrator

Why: the user's established workflow separates discussion context from execution without moving the conversation

- In either host, compile a plan without a start instruction, then give the instruction to start → compilation alone launches nothing; the original session creates a new tab in the same herdr workspace and starts an independent same-host build session from the plan and run file, without asking current versus new.

### gate-through-original-session — The build session waits at the human gate while the original session alerts the user and opens the review location

Why: the user reviews and responds in the original conversation

- The separate session reaches the human gate → it reports the gate and concrete review location to the original session and waits; the original alerts the user and opens what needs checking, without approving the result itself.

### feedback-through-original-session — The original session relays the user's notes and approvals unchanged to the existing build session, which alone advances pipeline state

Why: one conversation and one state writer prevent lost feedback and duplicate execution

- The user gives review notes, then requests a round or approves finish in the original conversation → the same build session receives the words unchanged and performs the existing CLI flow only on that user instruction; neither a second build nor duplicate state writes are started.
