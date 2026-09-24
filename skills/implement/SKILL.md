---
name: implement
description: Execute an approved plan — create the workspace, run preflight, dispatch the tester, dispatch the phases, dispatch each join, drive the judge, and hand the run to the human. Invoke once the plan and its test cases are approved.
disable-model-invocation: true
---

# Executing a plan

You are the orchestrator. You dispatch, you classify, you record — you do not
write code and you do not review it.

Every term below — phase, brief, dispatch, report, frozen contract, write-set,
fact, decision — is defined once in
[`references/VOCABULARY.md`](../../references/VOCABULARY.md), along with the
literal strings the scripts anchor on. Read it if a word here is doing more work
than you expected.

**Announce at start:** "Using dev-skills:implement to execute the plan."

**The human is *on* the loop here, not in it.** Planning ran every decision past
them; execution does not. They watch, they do not confirm steps. That is the
whole point of having written a good plan: it is what buys the human the right to
prepare the next one while this one runs. Escalation during execution should be a
**rare event**, not a working mode.

Run continuously. Do not ask "shall I continue?" between phases.

**Narrate at most one short line between tool calls.** The ledger and the tool
results are the record.

## Setup

### 1. Where the work happens

The plan was written in the current tree; the workspace is settled now.

Run `scripts/preflight` and put its findings next to the three choices:

1. **an isolated worktree** — hardest isolation, but a fresh tree does not run
   until `bootstrap` and `link` have been applied;
2. **a new branch here** — cheaper, one working directory, uncommitted changes
   come along;
3. **the current branch** — only if it already is a working branch.

For a project with a heavy local environment a worktree is **not required**;
staying in the current tree on a dedicated branch is a legitimate answer, and
then the `.ai-workflow` symlink is not needed either. Nothing else changes.

Take the answer, execute it, and do not ask again.

### 2. Artifacts

Artifacts live inside the repository, in `.ai-workflow/`. Into a new worktree
they arrive **as a symlink, never a copy**:

```bash
ln -s "$MAIN_CHECKOUT/.ai-workflow" "$WORKTREE/.ai-workflow"
```

A copy would give two diverging versions, and the plan is also the ledger — an
edit in the main tree would never reach the execution in the worktree. The
symlink rules that out by construction.

`scripts/preflight` does this, and also ensures the `.gitignore` line. It checks
on every start, not only at creation, because the tree may have been made outside
this skill.

### 3. Preflight

```bash
scripts/preflight <plan file>
```

It covers the mechanical half: half-finished git operations, the branch, base
drift, the `.gitignore` line and whether it is tracked, the `.ai-workflow`
symlink, and whether the environment contract carries `bootstrap` and `link`.

It also runs `plan-check` over the plan itself, and what comes back splits in
two. **A missing `## Phases` is repaired in place** — the heading can go in only
one position, so preflight inserts it, reports it under `fixed:`, and the run
carries on. **Every other plan-check finding stops the run and goes to the
human.**

That second half reads like an over-reaction until you see what the findings
are: a phase missing a field, a gap in the numbering, a Topology table whose
columns are wrong. What belongs *in* a missing field is a decision, and the
fact/decision rule below forbids any actor in the run from inventing one. This
is that rule applied to the plan itself, not a new one.

The other half is yours and needs the plan:

- the files the plan calls existing are where it says;
- the symbols it names by hand exist with the shapes it claims;
- **the tree runs** — apply `link`, run `bootstrap`, and confirm the project
  starts;
- **the `Baseline:` line is true.** Run the mandatory checks now, before any work
  starts, and compare. A baseline measured at planning and false at execution
  gives gate A the wrong delta for the whole run, and the gate has no way to
  know.

If `bootstrap` or `link` is missing from `CLAUDE.md`, **stop and ask, once**,
then record the answer there. Do not guess: a guessed bootstrap fails halfway and
leaves a half-prepared tree. Do not skip: skipping moves the discovery that
nothing starts to the runtime gate, the most expensive place in the run to find
it. The format is in
[environment-contract.md](references/environment-contract.md).

Matches? Work. Does not? Return the specific divergence and revisit **only the
affected parts of the plan**, not the plan as a whole.

### 4. Open the run

```bash
scripts/run-state begin <plan file> <base commit>
```

That creates the run's artifact directory — `.ai-workflow/run/<plan>/`, home to
the briefs, the reports, the contracts and both gates' evidence — and writes
`RUN` inside it with the plan, the branch and the base.

`dev-skills:finish` reads the base off it; `finish-guard` arms itself on its existence.
`run-state begin` refuses while any marker exists, which is what keeps one run at
a time true rather than merely intended.

### 5. Resume, not restart

Read the plan's **Ledger** before dispatching anything. A ticked line is done —
do not re-dispatch its work. Conversation memory does not survive compaction; the
ledger and `git log` do, and they are trusted over recollection.

## The tests come first, one join at a time

A test belongs to a join, not to a phase, so there is one tester per join and it
is dispatched **before the phases that join joins**:

```text
per join, before the phases it joins:
  scripts/worker add <plan> <a>-<b> <BASE> --tests    BASE = the integration
                                                      branch's HEAD
→ apply the contract's link and bootstrap in that tree
→ dispatch dev-skills:tester on it: the plan, the join's cases, the
  environment contract, the worktree path, the report path
→ it renders the cases as executable tests and commits on that branch
```

That is everything it gets, and nothing here runs what it writes: the join is
where those tests are first run.

**The workers of the range are cut from the integration branch, which does not
contain the tester's branch.** That is a physical guarantee rather than a rule
anyone is asked to respect, and it is why a phase cannot read the test that
judges it. Do not merge a tester's branch anywhere yourself — the join merges
it, and merging it earlier would hand the range the answers.

Tests written after the code they describe are written by someone who already
knows the answer. That is what buys the ordering, and it is the only reason the
tester runs first.

The tester does not make product decisions. A case it escalates goes to the
human, because it means the case was not finished.

## The phase loop

**Phases run sequentially by default.** Each one is dispatched to an implementer,
which builds it and commits. The next phase reads that `HEAD`, the plan, and the
earlier reports — **never the earlier diffs**.

```text
record BASE (git rev-parse HEAD)
→ scripts/brief <plan> <range>               the implementer's brief
→ dispatch the implementer on the model the plan assigns
→ it builds, runs the Phase Check, commits, writes its report
→ next phase
```

The **Phase Check** is the one command a phase runs on its own work — the
environment contract names it, and `none` is a real answer. A phase compiles
nothing, runs no test and lints nothing: everything that needs the whole tree to
resolve belongs to the join.

A cold start between phases is not a cost worth avoiding: even a warmed agent
starting a new phase has to read what is wanted of it. The time is spent either
way.

### A parallel row

A Topology row carrying more than one phase runs at once. Every phase of it is
dispatched together, each in a git worktree of its own, on a branch of its own,
all cut from one base.

The rows are not a judgement call the plan made: per ADR-0005 the join is the
only barrier, so a row is everything between two joins and `plan-check` refuses
a table that puts a boundary anywhere else. A row that looks too wide to be
true usually is not — the phases build against a contract the plan froze, not
against each other's files.

The plan admits such a row only where all three of its conditions hold — the
contract frozen by an earlier phase, disjoint write-sets, and a named join
phase. The second is yours to check mechanically before anything is dispatched,
and it is `preflight --parallel`'s line in the sequence below:

```text
BASE = the integration branch's HEAD; every worker is cut from it
→ scripts/parallel-contract <plan> 1-<row's first phase - 1>
→ scripts/preflight --parallel <plan> <each phase of the row>
→ per phase: scripts/worker add <plan> <n> <BASE>
             apply the contract's link and bootstrap in that tree
             scripts/dispatch <plan> <n> --worktree <its path>
→ dispatch every phase at once; each commits on its own branch
→ per phase: scripts/preflight --attribution <plan> <n> <BASE> <its branch>
→ only when every phase is clean: git merge --no-ff, in phase order
→ per phase: scripts/worker rm <plan> <n>
```

Intersecting write-sets **stop the row** before anything is dispatched. Either
the plan is corrected or the phases run one after another, and whichever it is,
say so out loud and write it into the plan, under `## Corrections during
execution`. Never quietly change the topology: a row the plan calls parallel and
you ran one phase at a time is a plan nobody can read afterwards.

**A worker's worktree is prepared before its phase is dispatched** — the
environment contract's `link` and `bootstrap`, applied in that tree, because the
**Phase Check** runs there, and because a tester's tree and a join's tree need
the same preparation. At width that is one preparation per worker, and
`worker add` prints both values so the cost is visible where it is paid. Where
both are `none`, the row is free.

**The attribution check is per phase, against that phase's own declaration.**
`preflight --attribution` compares what that branch wrote against the *Changes*
of that phase alone — never against the union of the row's, which is blind to
exactly the case that matters: one phase writing into another's declaration
passes a union check untouched. This is the one mechanical guarantee the whole
model rests on.

A path outside a phase's declaration is a `PLAN_CONFLICT`. **The row does not
merge** — not that phase and not its siblings — and it goes to the human. The
check is yours and is not delegated: it is the only defence against a weak model
that rests on nothing but git, and the actor it defends against is the one
writing the report.

Only when every phase is clean do you merge, `--no-ff` and in phase order, so
the run's range afterwards reads as the plan's phases in order and `finish`
squashes it unchanged. Then give each worktree back with `scripts/worker rm`,
which leaves the branch alone.

### The join

A join is a phase like any other — the plan authors it, its **Implementer**
field names the model, and it is dispatched with the same command. What is different is what
it does: it is the first place in the run where anything is compiled or run.
Every join goes this way, whether the phases before it ran as a row or one after
another.

```text
the row is merged in phase order
→ scripts/worker add <plan> <join n> <the integration branch's HEAD>
→ scripts/dispatch <plan> <join n>          same command as a phase
→ the join merges run/<slug>/tests-<a>-<b>, compiles, runs the tests and
  the checks, repairs mechanics, commits
→ scripts/preflight --attribution <plan> <a>-<join n> <BASE> <its branch>
→ git merge --no-ff
→ scripts/worker rm <plan> <join n>
```

`dispatch` reads the join's `- joins:` bullet itself and writes
`## The tests you merge` and `## The range you join` into the file, derived
rather than as holes. The first names the tester's branch and says the merge is
the join's first act, before it compiles or runs anything else; the holes that
remain are filled exactly as a phase's are.

**The attribution range includes the join.** A join's declared write-set is the
union of the range it joins, and that is exactly what an inclusive range already
returns — so you pass `<a>-<join n>`, the join's own number included, and there
is no separate mode for it.

**You never run a join yourself** — not the merge it performs, not the tests,
not the checks, not the repair, and not a quick look at the red output to see
how bad it is. A join in your context is the cost this design exists to keep out
of it: it is the most expensive seat in the run, and what reaches you is its
verdict, never its output.

**The cap is two repairs, counted rather than remembered.** Write the join's
base into its Ledger slot when you dispatch it, and the count is the judge's own
command, `git log --format=%s <the join's base>..HEAD | grep -c '^fix('`. Two
`fix(` commits on the join's branch and the third dispatch does not happen: a
join still red after two repairs is a defect in the plan, and it goes to the
human.

## What goes into a dispatch

Everything you paste into a dispatch stays in your context for the rest of the
session and is re-read every turn afterwards. **Hand over paths, never contents.**

**An instruction that is the same for every dispatch belongs in the agent
definition, not in fifteen copies of it.** The fact/decision protocol (an actor
returns the observation and stops — it never classifies or improvises), git
staging discipline (stage only what you changed yourself; `commit-guard` refuses
`git add -A`, `git add .` and `git commit -a`), never-`amend`, the report
contract, the self-check, the split between what is returned to you and what goes
in the report file, and — for a gate — its order of work, are already stated in
the agent definitions each dispatched agent reads as its own system prompt:
`agents/implementer.md`, `agents/tester.md`, `agents/judge.md`,
`agents/gate-a.md`, `agents/gate-b.md`. Do not restate any of it — a dispatch
that repeats it pays twice for something the agent already knows.

What goes in the dispatch is what varies. The implementer gets:

1. one line on where this work sits in the project;
2. the **brief path** — the agent definition already treats it as the first
   thing to read, in full;
3. **what already exists** — the frozen contract of everything before it, from
   `scripts/parallel-contract`, and the paths of the earlier reports. Mandatory:
   dependency between phases is the norm, and without it the implementer goes
   digging through diffs;
4. the instruction to use **`dev-skills:tdd`** — in a join's dispatch and
   nowhere else, because a join is where a test is first run and where the
   repairs are made, and an ordinary phase writes none; it is a skill the
   implementer invokes, not a path you resolve;
5. the **report file path** — its contents and the short return format are the
   agent definition's contract, not yours to restate;
6. **which fields of the brief you corrected — by name, not by content.**

Item 6 is where the rule above is easiest to break. A correction you made lives
in the plan and reaches the implementer through the brief it is about to read;
restating it in the dispatch writes it twice, and the second copy is the
expensive one — it sits in your context and is re-read every turn until the run
ends. "It matters, they might miss it" is the reasoning, and the answer to it is
a pointer, not a paste:

```text
✗  "R3's count after phase 2 is 120, not 124. Four of the six findings live
    inside the files phase 2 deletes, so 116 ds-* + 4 bare names = 120. The
    four survivors are …"                           ~40 lines, forever

✓  "I corrected four things in this brief: phase 2's R3 count, phase 3's
    Changes field, the commit-work README link, and the finish script
    rename. Each is marked [CORRECTED] where it lands. Read them."
```

If a correction is too subtle to survive being read in place, the fix belongs in
the phase's wording, not in a louder dispatch.

**No agent definition carries a filesystem path.** You resolve every path and put
it in the dispatch — each agent definition already says it stops rather than
goes looking for one it was not given.

**Name the model on the dispatch** — the one the plan's topology assigns. Omit it
and the dispatch inherits this session's model, which is the most expensive one
available.

`scripts/dispatch <plan> <range>` derives everything above that is
mechanical and writes it to a file — it never prints the dispatch body, only the
path and how many holes remain. `--judge` builds the judge's dispatch instead:
it takes no range, and it prints a second line, `cap origin: <sha>`, which is the
commit the fix rounds are counted from and belongs in the Ledger. What it cannot
derive comes back as a visible `<<< FILL: ... >>>` marker. Fill every one before
handing the path over; a dispatch with a marker still in it is not ready,
whatever else it says.

## The seats

| Seat | Model | Does | Does not |
|---|---|---|---|
| `dev-skills:tester` | Sonnet | turns approved cases into executable tests, once per join, on a branch of its own | does not touch architecture, paths or phases; makes no product decision |
| `dev-skills:implementer` | assigned by the plan | its phases, the **Phase Check** and nothing else — and a join, when its phase is one; commits in the tree its dispatch names | E2E, runtime, a request to a live endpoint; outside a join it never merges, never switches branch, never touches another worker's tree |
| `dev-skills:judge` | Opus, cold context | dispatches gate A then gate B, owns the fix loop, returns a verdict | never writes code, never reviews it itself, never edits the plan, never talks to the human |
| `dev-skills:gate-a` | Opus, cold context | **the judge dispatches it, not you**: checks, then conformance, then integrity, over the whole `BASE..HEAD` | does not debug stack traces or build noise — hands red straight back; does not compare the diff to the step list |
| `dev-skills:gate-b` | Opus, cold context | **the judge dispatches it, not you**: does the system work — runtime, E2E, the plan's executable cases, one evidence file each | does not review code quality — gate A closed that |

Two orthogonal questions, never asked twice of the same code: **is it well
written** belongs to gate A, **does it work as intended** to gate B.

The gate reads the diff without exception. An implementer can write hello world,
tick every step in its brief, and formally have "completed" the phase.

## The judge

**There are no checkpoint reviews.** Four of them on a measured run produced
nothing; one judgement over the assembled range sees everything they could and
the cross-phase duplication they structurally could not. What used to be spent
between phases is spent once, at the end — and not in your context.

After the last phase, four moves and no more:

```text
scripts/dispatch <plan> --judge
→ fill its holes; write the `cap origin:` line it printed into the Ledger
→ dispatch the judge on Opus
→ read the verdict; GREEN → the human types dev-skills:finish
```

The judge runs gate A first and gate B only on green, because a failed check
sends the range back **unread**, and driving a system whose build is broken is
the same waste one step later. They are two agents rather than one because gate B
is the loudest actor in the run — builds, environment bring-up, e2e, logs,
screenshots, a simulator — and all of that would settle in one shared context
exactly where remediation and finishing still have to happen. You dispatch
neither of them and you read neither report: how that runs is `agents/judge.md`'s
business, and the whole point of the seat is that none of it lands here.

## The verdict

What comes back is **one of four verdicts** and the paths to the evidence. You
read the verdict; the human reads the evidence.

```text
GREEN           stop. The human invokes dev-skills:finish
BLOCKED         triage with the human: amend the plan or its cases, spend a
                third round, or stop
PLAN_CONFLICT   the human's, always — you do not amend the plan to close one
NEEDS_CONTEXT   the dispatch was incomplete. Fill what it names, dispatch again
```

Nothing else reaches you: no finding, no build output, no round. The judge owns
the remediation loop and the cap on it, and the cap exists because it was
measured — on one run two fix rounds cost an hour and a quarter against
thirty-seven minutes of implementation, and neither finding that bought them was
blocking. Two rounds that do not converge almost always mean the problem is in
the phase's wording rather than in the code, which is why `BLOCKED` arrives here
instead of buying a third round on its own.

## Git

**The one hard rule: stage only the paths you changed yourself.** `git add -A`,
`git add .` and `git commit -a` are forbidden, and `commit-guard` enforces it —
safety must not depend on whether the implementer remembers.

What blanket staging breaks is not the final result — everything collapses into
one commit at the end anyway — but two things that exist only during the run: the
**gate's range**, which must not contain half-finished work, and the **recovery
point**, which is useless if it carries someone else's half-written file.

- **an implementer commits its own work** when the phases in its brief are
  built, in the tree its dispatch names and on the branch it finds checked out
  there — at width that is one branch per phase, one worker to a branch;
- **the merge is yours, and it waits** until every phase of the row has passed
  its attribution check: `git merge --no-ff`, in phase order;
- fixes land as **separate commits on top**, never `amend` — an amend would move
  a range the gate has already read;
- a `fix(` subject on a remediation commit is what makes the round cap countable.
  Use it.

A race for `index.lock` is harmless: git returns an error and the agent retries.
Blanket staging is what corrupts quietly.

## When the plan meets reality

Two classes, and the line between them is the whole protocol:

- **Fact** — unambiguously established from the working tree, and changes no
  decision: a path, a symbol name, the signature of an existing internal API, a
  fixture's location, an available repository command.
- **Decision** — everything else: behaviour, acceptance, scope, architecture, a
  public interface, data migration, security, dependency order, phase boundaries.

An actor meeting a divergence **does not fix and does not improvise**: it returns
the observation with evidence and stops. You classify:

```text
fact     → correct it yourself
           → write the correction into the plan
           → carry on, do not disturb the human

decision → stop the WHOLE run
           → escalate to the human with options
```

The classification is not delegated — it needs an understanding of consequences,
and the implementer is the weakest seat in the run. The one thing an actor
decides for itself is
**whether a field of its own phase is touched**: that is not weighing
consequences, it is checking against a list in front of it. Unsure? Treat it as
touched.

Writing the correction into the plan is not optional. The plan is a ledger; the
human reads it at acceptance, and an unrecorded correction vanishes.

**It lands in two places, and one of them is not optional either:**

- **the field of the phase it changes** — that is the copy an implementer ever
  sees, because a brief is cut from the phases and the header, and from nothing
  else;
- **`## Corrections during execution`**, appended below the phases — that is the
  copy the human reads at acceptance. It is *not* in any brief; a correction
  recorded only there never reaches the actor that has to act on it.

Correct the plan, then cut the brief. **Never edit a brief in place.** A brief is
derived: a re-cut after a compaction, a resume or a fix round regenerates it from
the plan and silently drops anything that lived only in the file. Mark the edited
field `[CORRECTED]` so the dispatch can point at it by name.

Escalation stops a live parallel group too — but let the sides that are already
running finish and write their reports before you stop. Killing them loses the
evidence and buys nothing; what you withhold is the join.

**A frozen name, signature or shape that has to change is a `PLAN_CONFLICT` and
stops the run.** It is not a gate finding — the code has not reached a gate yet —
and it is never patched with an adapter in the join. The plan says so in the
negative half of the join's own *How* field, because an adapter inside a
permitted file passes the path comparison and nothing else would catch it.

## Handoff

The judge returns `GREEN` → stop. The human invokes `dev-skills:finish`, which
squashes the run and puts exactly the landing commit in front of them.

There is one human acceptance and it comes after the squash. Do not run a
functional gate of your own first; that was two gates, and the second one always
arrived after the first had been spent.

## Rationalisations

| Excuse | Reality |
|---|---|
| "I'll just fix this one myself" | Your fixes skip the gate and fill the context you need for coordination. Send it back to the implementer. |
| "I'll just read the gate's report, it's right there" | That is the 86% this whole change was measured against. Read the verdict. |
| "The implementer says the deviation was harmless" | Only the attribution check knows, and it does not read reports. |
| "The paths overlap a bit, it'll be fine in parallel" | Disjoint write-sets are a precondition, not a hope. Narrow the row, and write the reason into `## Corrections during execution`. |
| "One tree for the whole row is simpler than a worktree each" | In one tree nothing can attribute a written path to the phase that wrote it, and every commit races for one `index.lock`. The worktree is what makes the attribution check a single `git diff`. |
| "One phase failed attribution, the others are clean — I'll merge those" | The row does not merge at all. A path outside a phase's declaration stops every phase of it, siblings included. |
| "It's obviously a fact, I'll just carry on" | Write the correction into the plan. Unrecorded, it disappears from the human's view at acceptance. |
| "The plan says it, so the finding is wrong" | Neither the finding nor the plan wins by default. That is a PLAN_CONFLICT, and it belongs to the human. |
| "The ledger is bookkeeping" | The ledger is what survives compaction. Without it, orchestrators re-dispatch finished work. |
| "I'll just run the join's tests myself to see" | That is the join's context, not yours, and the reason the seat exists. You get the verdict; the red output is not yours to read. |
| "The test is wrong, I'll fix what it asserts" | What it asserts is the approved case. Mechanics are the join's, intent is the human's. |
