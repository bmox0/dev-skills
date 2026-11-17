# Build

Building an approved plan: its phases, the E2E gate, the judge and the rounds, up to the human gate.

### judge-after-every-round — Every round ends with a primary judge before land and acceptance

Why: judgment uses the approved provider preset

- Complete phases, gate, judge, land, page and authorized acceptance, including a feedback round → ff-only finish uses the agreed ending and retains backups; existing judge dispositions and explicit land-hook exceptions remain visible and supported.
- Read every core skill, role and generated brief → shared rules come from AGENTS; planning, build coordination, first review and judge use primary; helpers, code, E2E and rechecks use secondary; no fixed provider/model or herdr-only requirement remains.

### judge-reads-the-round — After a round the judge reads only what the round was for and the re-check's results

Why: what the round did not touch should not have changed, and the re-check, not the judge, finds regressions

- The same plan after the round: the note has its commit and the targeted re-check is green. Run the judge → it reads the judge file, the round's notes and the re-check's results, but not the plan's other Done results or captures. It returns `pass:` after `land`, and the judge file is unchanged.
- The same plan at the human gate, after a round on one user note → the judge after it reads that note and the round's re-check, then lands.

### state-through-commands — CLI writes reject rendered drift and missing or stale prerequisites, including direct status changes

Why: a status cannot replace evidence or approval

- Validate a draft before consent → no approval; approve run then the current summary → build becomes eligible. Change run, plan or Spec → affected consent is stale; progress records survive reapproval.
- Attempt passed, request-link or merged shortcuts without required current judge, land, page or acceptance records → refused without state or target changes; supported request-link recording still works after a valid finish flow.
- Change the branch tree or approved planning content after a page/acceptance → stale stages are identified; passed and finish refuse until the required evidence and acceptance are current.

### act-with-a-reason — Recorded operational overrides preserve judgment but cannot manufacture missing approval, judge, land or page stages

Why: discretion does not authorize skipping the workflow

- Attempt passed, request-link or merged shortcuts without required current judge, land, page or acceptance records → refused without state or target changes; supported request-link recording still works after a valid finish flow.
- Complete phases, gate, judge, land, page and authorized acceptance, including a feedback round → ff-only finish uses the agreed ending and retains backups; existing judge dispositions and explicit land-hook exceptions remain visible and supported.

### phase-done-checked — A phase is done once its reported commits are on the branch, inside its territory or grants, with nothing of its territory left uncommitted or staged

Why: the check sits in the command the orchestrator calls anyway

- Phase 1 commits one path inside its territory and one outside, leaves one staged, and records its report. `phase done 1` → exit 1, naming both, and the phase stays `in progress`. Grant the outside path, commit the staged one and record the report again → `phase done 1` marks it `done` and prints phase 2 as ready.

### base-is-named — The base is the ref the orchestrator names; the CLI never picks one

Why: in real runs the base is almost never the default branch

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.

### epic-row-follows — Under an epic, the plan's row shows the plan's status after every change

Why: the row was forgotten in 3 of 5 runs

- Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.

### pre-5-1-adopted — Adopting a plan preserves progress without inferring run, summary or acceptance approvals

Why: historical progress is evidence rather than new authority

- Read a completed old run and adopt an unfinished one → completed history is unchanged; unfinished progress survives, but missing new approvals are not inferred at protected transitions.

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

### judge-file-by-code — Code writes the first judge file once with HEAD, UTC time and a supplied nonblank single-line engine identifier

Why: provenance describes the executor without restricting providers

- Record first verdicts with `--engine qwen`, `pi` and `hermes` → names reach the judge header; empty/multiline identifiers and missing prediction are refused; later-verdict rules remain intact.

### notes-in-their-words — Each note keeps its author's words, the user's or the judge's, and code alone numbers notes and rounds

Why: the round's implementer reads the note as it was said

- Record three user notes and mark one `task` → `<slug>.notes.md` lists two under Open and one under Tasks, in the words given, with their causes. `round start` takes the two; after one commit, `round done` → the heading reads ``## Round 1 · `<sha>` ``, and after two commits, `<first>..<last>`. `verdict round` → its notes are recorded with source `judge`, in the judge's words.

### page-from-records — The acceptance page describes current land and records, identifies evidence differences and binds acceptance to that result

Why: acceptance must describe the result being finished

- Attempt passed, request-link or merged shortcuts without required current judge, land, page or acceptance records → refused without state or target changes; supported request-link recording still works after a valid finish flow.
- Complete phases, gate, judge, land, page and authorized acceptance, including a feedback round → ff-only finish uses the agreed ending and retains backups; existing judge dispositions and explicit land-hook exceptions remain visible and supported.
- Change the branch tree or approved planning content after a page/acceptance → stale stages are identified; passed and finish refuse until the required evidence and acceptance are current.

### start-chosen — Summary approval starts nothing; a separate instruction chooses herdr, native independent session or manual handoff

Why: planning does not choose a session topology

- Follow planning through grill and the approved resume example → interview has no approval gate; the summary links the plan, explains phases, Spec, checks and limits within 350 words; approval alone starts nothing
- Start build by explicit herdr/native/manual instruction; review directly and through a designated orchestrator → the chosen contact controls acceptance within granted authority; resume reuses the existing writer and relayed words stay unchanged

### acceptance-contact — Questions and acceptance go to the user or designated orchestrator within granted authority, with unchanged relayed words and one writer

Why: responsibility rather than conversation identity controls a run

- Start build by explicit herdr/native/manual instruction; review directly and through a designated orchestrator → the chosen contact controls acceptance within granted authority; resume reuses the existing writer and relayed words stay unchanged
