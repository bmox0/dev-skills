This is history; the rules that hold now are in `docs/spec/`.

# Plan: the E2E gate and the judge in code

## Result

A round once skipped the full checks and reported a red word budget as green. Review and e2e returns drift in shape, and the level, the fix count, the judge file and the notes are redone by hand each run. After this plan, `pipeline.py` opens the gate: it writes the rules, computes the level and runs the full checks whenever HEAD is new. The reviewer and the e2e worker record through commands, and a fix takes the one list under a counter per cycle. The judge records its verdict and code writes `.judge.md`. Notes and rounds are records that render `<slug>.notes.md`, and code caps judge rounds and stops them early.

## Approach

The epic's Interfaces and the Approaches of plans 1–2 are the contract. A check cycle is the gate or one round, with its check runs, findings, results and fixes. Phase 1 opens the gate, phase 2 records findings, results and fixes, phase 3 the verdict, notes and rounds, and phase 4 rewrites the prose.

- `gate start` refuses before every phase is done, unless given `--note`. It, `fix done` and `round done` write and commit `docs/spec/` alone, then run the full checks, so the write before every re-check lives in code only (gap 4). A `spec write` refusal naming `docs/spec/` joins the one list; any other refuses with spec's own lines.
- Each `[checks].full` command runs on its own in the plan's tree, all of them even after a red one; a non-zero exit or a changed tree is red. A run records each exit code, a red output's tail and HEAD. It stands, printed with its SHA, while HEAD and the approved `[checks]` are unchanged. These are the rules orchestrators rewrote into every checks brief.
- The level is the plan's, raised to normal by any changed path outside its territories, granted ones included, `docs/spec/` not counted. It is recorded with the paths that raised it: the rule broke once in prose.
- Handed a brief, the reviewer and the e2e worker record each item with one command, whose fields are those their Returns name, "could not be judged" included. Without a brief they return as today. `status` prints the items in the Returns' shapes: free-text returns drifted (headings kept in one re-review of thirty, e2e lines in five shapes).
- `failed` covers a case the code keeps from being reached; `not reached` is only what the run file lacks. So code builds the one list, red checks, Defects and failed cases, with no sorting by hand. `approve` records the Done items and their `you check` marks.
- `fix start` gives the next fix every open item and is refused once the cycle's fixes are spent. After the re-check, an item found again survives: the same command, the same case, or a Defect the reviewer marks as one the fix took. It goes to Open, never into another fix; anything else new waits for the next fix.
- `brief reviewer|verify|fix|round|judge` fill what code knows, plus `--note`, each in its own file per cycle (gap 1). Fix and round implementers record a report as a phase's does, and `status` shows it (gap 2). On a re-check `brief verify` names the failed cases and those the orchestrator adds with `--cases`; with none it says so (gap 3).
- `brief judge` takes its case from the state and fills its inputs; after a round, only what `build#judge-reads-the-round` names. Above small, a case not `you check` without a result refuses it unless given `--note`. `judge.md` keeps how to read and decide, not what it is handed (gap 7).
- `verdict` records the return and a decision for every Open entry and Convention, refused while one is missing, and the first time the Prediction. The first verdict writes `.judge.md` with HEAD, a UTC time and the engine; nothing rewrites it.
- The orchestrator records the user's notes in their words, and `verdict round` records the judge's in its words, source `judge` (gap 5). Code numbers notes and rounds, keeps each round's range, one SHA for a one-commit round, and renders `<slug>.notes.md` in today's format.
- The caps, fixes per cycle and judge rounds per gate at the epic's numbers, and the three early-stop signs live only in `pipeline.py`. They stay out of this plan's Done and Spec, which reach `docs/spec/`. A user's round at the human gate starts a new count. A `verdict round` past the cap or on a sign records the stop with its reason and opens no round; the judge lands as on a pass, and build goes to the human gate.
- `run show` prints the allocated port and data directory on their own (gap 6).

## Out of scope

- The human gate page, stale results on it, `land`'s git and `finish`: plan 4. Until then build writes the page from `status`.
- Judgment: whether a finding is a Defect or one a fix took, which cases a fix touched, causes, what a round takes.
- `README.md` and `references/VOCABULARY.md`, whose gate lines describe 5.0, are outside row 3's territory. `references/CODEX.md` stays as it is.

## Done and Spec

```text
## Done

1. Run `scripts/check` and `scripts/test` → both exit 0, and no line in `workflow/`, `agents/` or `AGENTS.md` says how many fixes or judge rounds are allowed, or when rounds stop.
2. In a throwaway repo, a `small` plan with every phase done changes one path outside its territories and one under `docs/spec/`. Its `full` holds a passing command, a failing one and one that edits a tracked file. `gate start` → `docs/spec/` is committed alone; the level is `normal`, naming only the outside path; each command shows its exit code, the failing one its output tail, and the editing one is red. Again with no new commit → nothing runs, and the last result prints with its SHA; after a commit → they run.
3. A plan has a port and a data directory allocated and no placeholder in `[checks]`: `run show` → it prints both.
4. At the gate, record two Defects, a Convention, an Observation and what could not be judged; then Done 1 passed, Done 2 failed, and Done 3 not reached with its need → `status` prints the three lists as review returns them and one line per case as verify does. The one list holds the red check, both Defects and Done 2, nothing else. A result without a capture → refused.
5. `fix start` takes the one list, and `brief fix` holds each item's `file:line` and text. After its commit and report, `fix done` → the full checks run at the new HEAD. Record Done 2 failed again, the first Defect as one the fix took, and a new Defect → the first two go to Open, and the next fix takes only the new one. At code's cap, `fix start` → refused. `status` shows each fix with its items and commits.
6. After a fix, `brief verify --cases 1` → Done 2 and Done 1, nothing else; after a fix that failed nothing, with no `--cases` → no case to drive. `brief reviewer` → the fix's commits as its range, the items the fix took with their IDs, and the last check run.
7. `verdict pass` with a decision for each Open entry and Convention and a Prediction → `.judge.md` names the slug, HEAD's SHA, a UTC time ending in `Z` and the engine; a later verdict leaves it byte for byte. A verdict leaving one undecided → refused, naming it.
8. `brief judge` at the gate → the file holds the checks, the three lists, each Done result with its capture, the fixes with their commits, and Open. With a result missing → refused; with `--note` → written. After a round → a new file, the gate's unchanged, holding the judge file, the round's notes and its re-check, and no other Done result.
9. Record three user notes and mark one `task` → `<slug>.notes.md` lists two under Open and one under Tasks, in the words given, with their causes. `round start` takes the two; after one commit, `round done` → the heading reads ``## Round 1 · `<sha>` ``, and after two commits, `<first>..<last>`. `verdict round` → its notes are recorded with source `judge`, in the judge's words.
10. Order judge rounds in one gate → the one past code's cap is stopped: no round opens, and `status` shows the reason. In fresh gates, each sign stops a `verdict round` with its reason: rounds that leave no fewer new notes than they took, until code stops them; a check red, green after a fix, then red again; a cycle's fixes spent with a Defect standing. After a user's round at the human gate, the count starts afresh.
11. In a throwaway repo, run `runweld build` from this checkout on a two-phase plan to the human gate → the full checks run only through the CLI, the reviewer and the e2e worker record through their briefs, the judge records its verdict, and no one writes `.judge.md` or the notes file by hand. `runweld review` on a range without a plan → the three lists as before — you check
12. At the gate before any fix, a case recorded `failed`: `brief verify --cases 2` → the brief lists case 2; a new `passed` result supersedes it, and the one list no longer holds it.
13. `brief verify` → it says to run each case's command exactly as written, one shell call per case; `brief reviewer`, `brief verify` and `brief fix` → each record command is printed in full, never through a shell variable.
14. A fix that commits nothing: `fix report` without `--commit` → recorded; after `fix done`, `brief reviewer` → it says the fix made no commit, with no range.
15. After a fix, `brief reviewer` and `brief verify` → files named for that fix's re-check; the gate's `…-gate.md` briefs unchanged.
16. `verdict --help` → it lists the `--decide` actions and says `--predicted` goes only on the first verdict.
17. After a round whose re-check has no case to drive, `brief judge` → it states `no case to drive` for verify; after one with cases, their results.

## Spec

+ build#checks-by-code — The full checks run in code at the gate and at every re-check, whenever HEAD or the approved checks are new
  Why: a round that skipped them reported a red word budget as green
  Done: 2
+ build#level-from-diff — The gate's level is the plan's, raised to normal by any changed path outside the plan's territories other than `docs/spec/`
  Why: the level follows from the diff; a slip in this rule once shipped untested
  Done: 2
+ build#findings-recorded — With a plan, the reviewer and the e2e worker record each finding and result through the CLI, and every reader sees them from there
  Why: free-text returns drifted in shape, so readers parsed them by guess
  Done: 4
+ build#survivor-to-open — A fix takes every open item of the one list; an item found again after its fix goes to Open and gets no second fix
  Why: a second try at the same finding repeats the first; the judge or the user decides it
  Done: 5
+ build#caps-in-code — Code alone caps fixes per check cycle and judge rounds per gate, and stops rounds that stop converging; no cap or threshold appears in prose an agent reads
  Why: a number in prose becomes a quota
  Done: 1, 5, 10
+ build#judge-file-by-code — `<slug>.judge.md` is written once, by code, from the first verdict, with HEAD, a UTC time and the engine
  Why: written by hand, its format drifted: time zones, a slug without its date
  Done: 7
+ build#notes-in-their-words — Each note keeps its author's words, the user's or the judge's, and code alone numbers notes and rounds
  Why: the round's implementer reads the note as it was said
  Done: 9
```
