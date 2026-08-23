---
name: implement
description: Execute an approved plan — create the workspace, run preflight, write the tests, dispatch the phases, join the parallel groups, drive both gates, and hand the run to the human. Invoke once the plan and its test cases are approved.
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

## The tests come first

Dispatch **`dev-skills:test-writer`** before the first phase, with the plan's
user stories, its test cases, the plan itself and the environment contract.

It writes the runnable cases as executable tests and commits them as their own
commit. Tests written after the code they describe are written by someone who
already knows the answer.

A case marked `NOT-YET-RUNNABLE` waits for something that does not exist yet.
Dispatch the test writer again **immediately before the parallel group that
depends on it** — not at some convenient moment in between. A group starts from
one `HEAD`; a test landing after that is a test half the group never saw.

The test writer does not make product decisions. A case it escalates goes to the
human, because it means the case was not finished.

## The phase loop

**Phases run sequentially by default.** Each one is dispatched to an implementer,
which builds it and commits. The next phase reads that `HEAD`, the plan, and the
earlier reports — **never the earlier diffs**.

```text
record BASE (git rev-parse HEAD)
→ scripts/brief <plan> <range>               the implementer's brief
→ dispatch the implementer on the model the plan assigns
→ it builds, runs its checks last, commits, writes its report
→ next phase
```

A cold start between phases is not a cost worth avoiding: even a warmed agent
starting a new phase has to read what is wanted of it. The time is spent either
way.

### A parallel group

The plan admits a group only where all three of its conditions hold — the
contract frozen by an earlier phase, disjoint write-sets, and a named join phase.
Check the second one yourself before dispatching anything:

```bash
scripts/preflight --parallel <plan file> <range A> <range B> [...]
```

Intersecting write-sets **stop the group.** Either the plan is corrected or the
phases run sequentially, and whichever it is, say so out loud and write it into
the plan. Never quietly change the topology: a group the plan calls parallel and
you ran sequentially is a plan nobody can read afterwards.

Then:

```text
one HEAD for the whole group
→ scripts/parallel-contract <plan> <range>   the frozen contract both sides build against
→ dispatch every side at once, each with its own brief
→ each side edits only its own paths and returns a report — none of them commits
→ you compare the actual paths against the union of the phases' Changes
→ you run the phase checks
→ you make ONE join commit
→ the join phase is dispatched on that commit
```

**The agents in a group do not commit.** One join commit per group is what keeps
the range readable and gives the path comparison a single place to happen.
Letting each side commit would put a half-built group into a range that gate A
may already be reading.

The path comparison is yours and is not delegated. It is the only defence against
a weak model that rests on nothing but git, and the actor it defends against is
the one writing the report.

If the actual paths fall outside the union, that is a `PLAN_CONFLICT` — do not
join, and take it to the human.

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
`agents/implementer.md`, `agents/test-writer.md`, `agents/gate-a.md`,
`agents/gate-b.md`. Do not restate any of it — a dispatch that repeats it pays
twice for something the agent already knows.

What goes in the dispatch is what varies. The implementer gets:

1. one line on where this work sits in the project;
2. the **brief path** — the agent definition already treats it as the first
   thing to read, in full;
3. **what already exists** — the frozen contract of everything before it, from
   `scripts/parallel-contract`, and the paths of the earlier reports. Mandatory:
   dependency between phases is the norm, and without it the implementer goes
   digging through diffs;
4. the instruction to use **`dev-skills:tdd`**, if the plan says this work has tests —
   it is a skill the implementer invokes, not a path you resolve;
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
path and how many holes remain. `--gate-a` builds the code gate's dispatch
instead. What it cannot derive comes back as a visible `<<< FILL: ... >>>`
marker. Fill every one before handing the path over; a dispatch with a marker
still in it is not ready, whatever else it says.

## The seats

| Seat | Model | Does | Does not |
|---|---|---|---|
| `dev-skills:test-writer` | Sonnet | turns approved cases into executable tests, each named with its `TC-ID` | does not touch architecture, paths or phases; makes no product decision |
| `dev-skills:implementer` | assigned by the plan | its phases, TDD where the plan says there are tests; static checks last, at its final commit | E2E, runtime, a request to a live endpoint; does not commit inside a parallel group |
| `dev-skills:gate-a` | Opus, cold context | checks, then conformance, then integrity, over the whole `BASE..HEAD` | does not debug stack traces or build noise — hands red straight back; does not compare the diff to the step list |
| `dev-skills:gate-b` | Opus, cold context | does the system work: runtime, E2E, the plan's executable cases, one evidence file each | does not review code quality — gate A closed that |

Two orthogonal questions, never asked twice of the same code: **is it well
written** belongs to gate A, **does it work as intended** to gate B.

The gate reads the diff without exception. An implementer can write hello world,
pass a test on it, and formally have "completed" the phase.

## The two gates

**There are no checkpoint reviews.** Four of them on a measured run produced
nothing; one gate over the assembled range sees everything they could and the
cross-phase duplication they structurally could not. What used to be spent
between phases is spent once, at the end, on more.

After the last phase, in this order and never at once:

```text
scripts/review-package <plan> BASE HEAD   the whole range
→ scripts/dispatch <plan> --gate-a
→ dispatch gate A: checks, then conformance, then integrity
→ green → dispatch gate B on the executable cases and the plan's moments
→ green → squash, then the human
```

Gate A first because a failed check sends the range back **unread**, and gate B
driving a system whose build is broken is the same waste one step later.

They are two agents rather than one because gate B is the loudest actor in the
run — builds, environment bring-up, e2e, logs, screenshots, a simulator — and all
of that would settle in a shared context exactly before remediation and
finishing. The second cold start is the price, and it was priced in.

Each gate returns **a verdict and a path**. You do not read its report into your
context; you read the verdict, and the human reads the evidence.

## The fix loop

**Only a `BLOCKER` opens a fix round.**

An `ADVISORY` travels to the human alongside the diff, counted on one line —
`Unresolved advisories: n`. It never buys an implementer pass and a gate pass.
This is the largest single saving in the redesign, and it is measured: on one run
two fix rounds cost an hour and a quarter against thirty-seven minutes of
implementation, and neither finding that bought them was blocking.

For a `BLOCKER`:

- the **same implementer** fixes first — it is warm, it does not need to re-read
  the plan, and it is pointed at the specific place;
- if that round does not close it, a **new implementer** on a cold context;
- **two rounds, and the cap is checked mechanically.**

### Checking the cap

The cap has existed as prose since before this rewrite and it did not hold: a
measured run took four fix rounds with no escalation at all. A rule enforced by
judgement is a rule that goes when the judgement is busy.

Record the `HEAD` at the first gate dispatch in the ledger. Before every later
gate dispatch, count:

```bash
git log --format=%s <head at the first gate dispatch>..HEAD | grep -c '^fix('
```

Two comparable numbers, no model judgement — the same class of check as comparing
paths. **At two, the third gate dispatch does not happen.** The run goes to
triage: the human decides whether to amend the plan or its cases, spend a third
round, or stop.

Two rounds that do not converge almost always mean the problem is in the phase's
wording, not in the code.

Findings that conflict with what the plan mandates are not fixed and not
dismissed: that is a `PLAN_CONFLICT`, and it goes to the human.

## Git

**The one hard rule: stage only the paths you changed yourself.** `git add -A`,
`git add .` and `git commit -a` are forbidden, and `commit-guard` enforces it —
safety must not depend on whether the implementer remembers.

What blanket staging breaks is not the final result — everything collapses into
one commit at the end anyway — but two things that exist only during the run: the
**gate's range**, which must not contain half-finished work, and the **recovery
point**, which is useless if it carries someone else's half-written file.

- a sequential phase's implementer commits its own work when the phase is built;
- **a parallel group's agents do not commit.** You compare the paths, run the
  checks, and make one join commit for the group;
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
and it is never patched with an adapter in the join phase. The plan's join phase
says so in the negative half of its *How* field, because an adapter inside a
permitted file passes the path comparison and nothing else would catch it.

## Handoff

Both gates green → stop. The human invokes `dev-skills:finish`, which squashes
the run and puts exactly the landing commit in front of them.

There is one human acceptance and it comes after the squash. Do not run a
functional gate of your own first; that was two gates, and the second one always
arrived after the first had been spent.

## Rationalisations

| Excuse | Reality |
|---|---|
| "I'll just fix this one myself" | Your fixes skip the gate and fill the context you need for coordination. Send it back to the implementer. |
| "One more round will converge" | Past two rounds it does not. The failure is in the phase's wording; escalate. Count the `fix(` commits rather than trusting the feeling. |
| "It's only an advisory, but it's quick" | Quick is not the cost. A round is an implementer pass plus a gate pass, and the human never sees the one that was not worth running. |
| "The gate re-ran the same checks, that's waste" | It re-runs them only when the SHA moved. When it matches, it takes the report. That is the whole deal. |
| "The implementer says the deviation was harmless" | Only the path comparison knows, and it does not read reports. |
| "The paths overlap a bit, it'll be fine in parallel" | Disjoint write-sets are a precondition, not a hope. Run them sequentially and write down that you did. |
| "It's obviously a fact, I'll just carry on" | Write the correction into the plan. Unrecorded, it disappears from the human's view at acceptance. |
| "The plan says it, so the finding is wrong" | Neither the finding nor the plan wins by default. That is a PLAN_CONFLICT, and it belongs to the human. |
| "The ledger is bookkeeping" | The ledger is what survives compaction. Without it, orchestrators re-dispatch finished work. |
