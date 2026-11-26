This is history; the rules that hold now are in `docs/spec/`.

# Plan: the plan's state and the build in one CLI

## Result

Orchestrators rewrite statuses by hand 2–13 times a run, forget the epic's row, and nobody checks a phase's commits. After this plan, `workflow/build/pipeline.py` keeps the plan's state in `<slug>.json`. `approve` compiles the plan with a strict check. `build start` and `phase start/done` move the statuses and check each phase's commits. `status` says what is ready, `brief` writes what an agent needs, and `spec.py` becomes `pipeline.py spec`. `plan`, `build`, `spec`, `grill` and the implementer call the CLI.

## Approach

The epic's Interfaces are the contract. The parser leaves `spec.py` first, so `approve` and `spec` read the plan through one code path. Then come the state, the build commands, and the prose that calls them.

- `<slug>` is the plan file's name without `.md`, date included, as the notes and judge files already have it — an agent once ran `sed` on the name without the date.
- A render rewrites only the lines code owns: the Status line, each phase's status, and one line saying the file is rendered. Every other line stays byte for byte, so the rendered file is still the plan format for readers, `spec check` and the 5.0.2 build.
- The plan's text changes after approval by an edit and `approve` again. It recompiles and keeps every record. It refuses an edited code-owned line, naming that line's command, and a started phase that is gone or renumbered. A `## Spec` fix at the gate and a round's new Done item are real edits.
- Any other write refuses while the file differs from its last render; reads report the drift. Otherwise a hand edit would vanish silently, and `status` must still print after a compaction.
- From `## Human gate` on, the file is kept as written: the page and `land`'s commits are hand-written until plan 4.
- Every code-owned value has a command, which records the time, a note and a SHA. The plan's status takes any value in its list, forward or back. The base moves when a rebase moves it.
- An agent acting against a fact a command reports passes `--note` with its reason, for example starting a phase before its waits are done. Without the note the command refuses. This is the one way a deviation reaches the gate page.
- `build start` requires `--base <ref>`, so code never picks the base. It reports a dirty tree and the checked-out branch as facts, and cuts the branch here, or in a worktree with `--worktree`.
- `phase done` checks the plan's recorded tree for four things: a recorded report, its commits on the branch after the base, their paths inside the territory or grants, and nothing of the territory uncommitted or staged. If one fails, it exits 1 and the phase stays `in progress`.
- `owner <path>` names the running phase whose territory or grants hold the path. A grant is recorded, and `phase done` honours it. Granting a path that another running phase owns is refused with the owner's name.
- Rulings and product calls are one record: the question as asked, where it came from, the answer, why, and the cost if wrong. Whoever made the call writes it. `status` lists the records for the gate page until plan 4 renders them.
- The implementer records its report: what became true, the skills read, the interfaces changed, the checks and their result, and the commits. Its final message holds only what the orchestrator must act on, so there is one copy, and later briefs read it.
- `brief` writes a file beside the plan, and the dispatch prompt is the file's path. A phase's brief carries the reports of the phases it waits for and the CLI's absolute command. The judge's brief carries the absolute path of `judge.md`, with its case and inputs in the note until plan 3.
- The `Epic:` line names the plan's row. The row's Status cell follows every status change, and nothing else in the epic is touched — the row was forgotten in 3 of 5 runs.
- Problems in the plan file keep `spec check`'s form, `<plan>:<line>: <message>`, and `approve`'s shape check uses it too. `<code>: … — fix: …` is for arguments and state, so an unchanged `spec.test.sh` proves nothing broke.
- A plan with no JSON is adopted by `approve` as its file stands. Its status, branch, base and phase statuses become the first records, so a plan mid-build goes on where it is. Every command except `spec` refuses such a plan, with that fix.
- Prose a command replaces is deleted, and word budgets follow the new counts.

## Out of scope

- `gate.md`, `rounds.md` and `finish` keep their hand edits for now: the base after a conflict, a round's Done item, and `merged`. Plans 3 and 4 own those files.
- Briefs for the reviewer, the e2e worker and fix implementers, and checks commands in briefs: plans 2 and 3.

## Done and Spec

```text
## Done

1. Run `scripts/check` and `scripts/test` → both exit 0. `workflow/spec/spec.py` is gone, and nothing outside `.runweld/workflow/` and `docs/spec/` names it. `git diff a0a41ac -- test/cli/spec.test.sh` touches only the entry and the program's name in one message.
2. In a throwaway repo, run `spec list`, `show`, `check` and `write` through `pipeline.py`, and through `spec.py` from `a0a41ac` → both give the same output, exit codes and files.
3. Approve a plan whose phase 3 waits for a phase 9, which has two unordered phases sharing a directory, and which names a missing Skills path → exit 1, with one `<plan>:<line>:` line per problem and no JSON. Fix the problems and approve again → the JSON exists, and the file differs from the draft only in Status and the rendered line. The output ends with the graph, the level and the word count.
4. Under a throwaway epic, run `build start --base <tag>` → the branch starts at the tag, and Status reads `building` with the tag's SHA. The epic's row reads `building`, and `status` shows phase 1 as ready.
5. Edit the Status line by hand, then run `phase start 1` → refused, naming the line and its command, and `status` still prints, showing the drift. Instead, edit a Done item and run `approve` → the plan is recompiled and every status is kept.
6. Phase 1 commits one path inside its territory and one outside, leaves one staged, and records its report. `phase done 1` → exit 1, naming both, and the phase stays `in progress`. Grant the outside path, commit the staged one and record the report again → `phase done 1` marks it `done` and prints phase 2 as ready.
7. Run `phase start 3` before phase 2 is done → refused; with `--note` → started, and `status` shows the note. Run `phase start 1` on the done phase with a note → back to `in progress`, with the note and HEAD's SHA.
8. Write two records at the same moment → both are in the JSON, and it parses. A recorded ruling → `status` lists its question, answer, why and cost.
9. Run `brief implementer 2 --note "<text>"` → it prints a path. The file holds the absolute paths of the plan, the tree and the CLI. It also holds the branch, the base, HEAD, phase 2's territory and Skills, phase 1's report, and the note. `brief judge` → the file holds the absolute path of an existing `judge.md`.
10. Take a plan at `building` with phase 1 `done` and no JSON, and run `phase start 2` → refused, with a fix naming `approve`. Run `approve` → phase 1 is still `done`, and phase 2 is ready.
11. In a throwaway repo, run `runweld plan`, then `runweld build`, from this checkout on a two-phase plan → every status, the base and the epic's row change through the CLI, nobody edits the plan file by hand, and each report is a record — you check

## Spec

+ spec#one-parser — The plan is parsed in one place, the pipeline's CLI, whose `spec` commands replace `spec.py`
  Why: two parsers of one plan drift apart (GSD ADR-3524)
  Done: 1, 2
+ build#state-through-commands — After approval a plan's state changes only through the CLI, and a write refuses while the plan file differs from its last render
  Why: one writer per fact; a hand edit would vanish at the next render
  Done: 4, 5
+ build#act-with-a-reason — An agent may act against a fact the CLI reports, with a reason the CLI records for the human gate
  Why: code states facts, agents keep the judgment
  Done: 6, 7
+ build#phase-done-checked — A phase is done once its reported commits are on the branch, inside its territory or grants, with nothing of its territory left uncommitted or staged
  Why: the check sits in the command the orchestrator calls anyway
  Done: 6
+ build#base-is-named — The base is the ref the orchestrator names; the CLI never picks one
  Why: in real runs the base is almost never the default branch
  Done: 4
+ build#epic-row-follows — Under an epic, the plan's row shows the plan's status after every change
  Why: the row was forgotten in 3 of 5 runs
  Done: 4
+ build#recover-plan-state — A plan without state is adopted by `approve` as its file stands; no other command but `spec` runs on it
  Why: a plan mid-build keeps its recorded progress
  Done: 10
```
