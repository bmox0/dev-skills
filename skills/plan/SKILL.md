---
name: plan
description: Write the implementation plan — the contract a cold, cheap implementer builds from. Use when the human moves from working out what to build to writing it down ("write the plan", "переходим к плану"), when a grilling has ended in alignment, or when they name an entry from an existing epic's plan list.
---

# Writing a plan

The plan is the artifact the whole workflow rests on. It is what lets a weak
model build well, and what lets the human step off step-by-step supervision
during execution. Everything downstream is only as good as this file.

**Announce at start:** "Using dev-skills:plan to write the implementation plan."

**A plan is always created, and always as a file.** There is no inline mode. It
is a ledger as well as a contract — its checkboxes have to live somewhere.
Length is set by the task; a short task gives a short file.

Write it to `.ai-workflow/plans/YYYY-MM-DD-<name>.md`, and make sure the
repository ignores that directory:

```bash
grep -qxF '.ai-workflow' .gitignore || printf '.ai-workflow\n' >> .gitignore
```

**Without a trailing slash** — a pattern with one matches directories only, and
in a worktree `.ai-workflow` is a symlink, which git sees as a file. If the exact
line is absent, add it; do not analyse the variants already there.

## Plan in the current tree

Planning happens where you are. The branch or worktree is created at the start of
execution, by `dev-skills:implement`, not here.

## Entry with an existing epic

An epic that produced more than one plan makes this skill a starting point of its
own: the human names an entry from its list and planning begins there. The
grilling is not repeated — the alignment is already recorded in the epic's
*Decisions taken*.

On that entry:

- read the epic whole: decisions, glossary, the plan list with its dependencies;
- check that the entries this one depends on are closed. If they are not, say so
  and do not plan on top of a result that does not exist;
- plan **only the entry named**. Neighbouring entries do not get pulled in, however
  small they look;
- **do not reopen the epic's decisions.** If a decision surfaces at plan level
  that the epic does not contain, stop and propose grilling. Do not settle it
  here.

That last one is the whole boundary between the two levels: the epic holds
decisions, the plan holds mechanics. A planner that settles something on the
epic's behalf diverges from every other plan in the list, because none of them
saw it.

Set the entry's state to *in progress* in the epic when the plan is created.
That, and `dev-skills:finish` marking it *done*, are the only writes to an epic after it
exists.

## The completeness contract

Every plan carries all of these. A section with nothing in it says so with a
dash — the dash is an assertion by the planner, not tidiness.

| Section | Why | Read by |
|---|---|---|
| **Goal** | what we are doing, in your own words | everyone; `dev-skills:finish` derives the commit message from it |
| **Epic**, or "single-cycle" | where the shared context is, if there is any | everyone |
| `Norms:` | the paths that count as an approved source of a convention | the code gate |
| `Baseline:` | what the mandatory checks produce before any work starts | the code gate |
| **User stories** | actor, action, outcome — what the work is for | everyone |
| **Moments** | what the person is put in front of, and in what order | planner, implementer, gate B |
| **Constraints** and **Out of scope** | where not to go | implementer |
| **What the final gate proves** | the verification contract for this kind of task | the runtime gate |
| **Test seams** | where we check. Existing beats new, highest level that works, the ideal number of new seams is zero | implementer, reviewer |
| **Paths and existing abstractions** | so nobody researches the codebase again | implementer, reviewer |
| **Test cases** | what gets checked — and nothing outside it is | test writer, both gates |
| **Topology** | how the phases are grouped, their relations, the model per group | orchestrator |
| **Phases** | bounded units of execution, seven fields each | implementer, reviewer |
| **Final-gate scenarios** | the runtime projection of the test cases | the runtime gate, the human at acceptance |
| **Ledger** | the run's record and its resume point after a compaction | orchestrator |

If the work puts something new in front of a person — a screen, a prompt, a
message, the output of a command — [references/moments.md](references/moments.md)
says how a storyboard is written and when you offer to draw one. Work that
changes only a server, a script or a schema puts nothing new in front of anyone:
its section is a dash, and that file stays unread.

There is **no `Commit` section**. The Goal is enough: the actor assembling the
commit reads the goal and the result.

Seams live here rather than in the epic, because an epic does not always exist and
every plan needs them. Put them to the human as their own question.

The same reason puts the stories and the cases here. An epic exists only when a
task needs more than one plan; a story that lived only in an epic would have
nowhere to live in the single-plan case, which is most cases.

## The skeleton

The heading order, literally. Reproduce it and the container is right:

```markdown
# <plan title>

Norms: …
Baseline: …

## Goal
## Epic
## User stories
## Moments
## Constraints
## Out of scope
## What the final gate proves
## Test seams
## Paths and existing abstractions
## Test cases
## Topology
## Phases
### Phase 1. <what becomes true>
### Phase 2. <what becomes true>
## Final-gate scenarios
## Ledger
```

`## Phases` is a container, not a decoration. Without it the headings below it
are not something a script can cut: `brief` hard-stops, and `plan-check` — run
before you present the plan, see below — repairs the omission rather than let a
run start on it. Writing the container yourself is how it never comes up.

The strings the scripts anchor on — these headings, the seven field names, the
Topology columns, the artifact names derived from a phase range — are written out
once, in [`references/VOCABULARY.md`](../../references/VOCABULARY.md), together
with the vocabulary every artifact in a run uses. The skeleton is the shape; that
file is the letter. Neither is a copy of the other.

## Two lines in the header

Both are bare lines above `## Goal`, so every brief and every gate carries them:

```markdown
Norms: docs/adr/0007-errors.md, CONTEXT.md
Baseline: `pnpm typecheck` → 150 errors, all outside `src/features/auth/`
```

**`Norms:`** lists the approved documents — ADRs, `CONTEXT.md`, a coding standard
— that count as a source of convention for this work. It is the top rung of the
review's ladder, and what is not on the line, the review does not go looking for.
That makes completeness yours: a convention you leave off is a convention nobody
enforces. A plan with no `Norms:` line at all is reviewed under the older, more
legacy-tolerant rule — so leaving it out is a decision, not a shortcut.

**`Baseline:`** records what the mandatory checks produce **before** any work
starts, so the gate judges the delta rather than the absolute. A project with a
hundred and fifty pre-existing typecheck errors, a build that was already broken,
or — on the `dev-skills:bug` route — a deliberately failing committed test, is
normal. A gate that bounces on absolute red never reads a line of the diff, which
is the one thing it is there to do. Run the checks yourself and write down what
you got. No line means "everything was green before we started", and that is an
assertion, not a default.

## User stories

Actor, action, outcome, in the language the human used rather than the language
of the code. Give each an ID:

```markdown
- **US-1.** A signed-out visitor submits an email and a password and gets an
  account they can sign in with.
- **US-2.** A visitor who submits an address the system will not accept is told
  which part was rejected, and keeps what they typed.
```

The IDs matter because the test cases point back at them. That pointer turns "is
this story covered?" into a question with an answer instead of an impression.

Stories are not phases. A phase is a unit of execution and can be invisible from
outside; a story is what the work is for. One story usually spans several phases,
and a phase serving no story is worth a question at the gate.

## Anatomy of a phase

Write a phase as if the implementer is a very good engineer **who knows nothing
about this project**. They must not have to find a file, settle an approach, or
check your work. Everything they need is in the phase or in the plan's header.

"Do A, do B" is therefore not a phase. Only the header and the phases reach the
brief; anything absent from them the implementer either invents or goes looking
for — which is exactly what the plan exists to prevent.

### Three levels of fixing a decision

A decision is not fixed by being mentioned. There are three levels, and which one
a thing sits on is not a matter of taste.

**Written out verbatim, in a fenced block:** the type, interface or signature of
anything that crosses a phase boundary or a module boundary. Not described and
not promised — written, in the language of the codebase, so the implementer can
lift it:

```ts
export type CreateUserInput = { email: string; password: string }
export function createUser(input: CreateUserInput): Promise<Result<User, CreateUserError>>
```

Writing the signature out is where the design errors surface — the argument that
has nowhere to come from, the error case with no channel, the two callers that
need different shapes. A planner who writes "the signature does not change"
instead has not taken that decision; they have handed it to the implementer, the
one actor in the run with no authority to take it. Which field it lands in
follows from who reads it: *Frozen for later phases* when a later phase builds on
it, *How* when it is this phase's own surface and nothing downstream depends on
the shape.

**Fixed in prose:** every other decision — every path touched, including test
paths; the abstractions used, by name and with their path; which test cases the
phase makes true; edge cases and the behaviour on them; what counts as an error
and how it shows; what not to touch and what not to introduce; order, where order
carries meaning.

**Never appears:** function bodies, test code, imports, style. That is typing,
not deciding. The planner saves nothing by omitting it, because the planner
should not be writing it at all.

**Sufficiency test:** two competent engineers reading this phase should write
functionally identical code. If they would differ in something that would have to
be redone, a decision is missing — add it. If they differ only in form, the
reviewer closes that against the repository's conventions.

Do not economise on density. A thin plan is paid for twice: once in a bad
decision, and again in the rework.

### The seven fields

The subheadings are **fixed strings**. This is not formatting: the orchestrator
cuts a phase into a brief mechanically, and mechanical assembly needs stable
anchors.

| Field | What it carries |
|---|---|
| **Becomes true** | the observable result of the phase; it also sets the phase's size |
| **Changes** | paths *and* entities: a symbol, a function, a region — not only a file |
| **How** | named abstractions with paths, plus the negative side: what not to introduce |
| **Do not touch** | only conflicts *inside* paths already granted |
| **Frozen for later phases** | the names, signatures and data shapes later phases build on — written out, never referred to |
| **Verification** | the approved test cases this phase makes true, by ID |
| **Steps** | the order of work, with checkboxes |

**All seven are mandatory; absence is written as a dash.** `Do not touch: —` means
"there is no neighbouring conflict", not "I forgot to think about it". There is no
other way to tell forgetfulness from a considered nothing, and in *Frozen for
later phases* that slip costs the next phase range a stop. The presence of all
seven subheadings is checked by grep, with no model judgement involved.

In a typical phase three of the seven are dashes. That is cheaper than one
invisible omission.

### The form

````markdown
### Phase 3. Pressing the button switches the theme

**Becomes true**
- clicking the button toggles the theme between `light` and `dark`
- the chosen value survives a page reload

**Changes**
- `src/features/theme/ThemeToggle.tsx` — the `onClick` handler

**How**
- use the existing `useTheme` (`src/shared/theme/useTheme.ts`); it already holds
  `setTheme` and persists to `localStorage`
- do not introduce a new store or context

**Do not touch**
- the button's markup in `ThemeToggle.tsx` — it belongs to phase 2

**Frozen for later phases**
- —

**Verification**
- cases: TC-4, TC-5, TC-6, TC-7

**Steps**
- [ ] wire `useTheme` into `ThemeToggle`
- [ ] hang the toggle on `onClick`
- [ ] take TC-4 through TC-7 green
````

### Sizing a phase

The unit of review is the **whole run** — one gate, over everything. Splitting
phases therefore buys no extra scrutiny and costs no extra review; only the
planner pays, in fields written. The floor is meaning, not the cost of starting
an agent.

The criterion comes from a field that is mandatory anyway:

- **from below** — a phase must have its own observable result, stated as a claim
  about behaviour or about an artifact something else relies on;
- **from above** — if *Becomes true* has to be assembled with "and" out of
  unrelated claims, that is two phases.

```text
"clicking switches the theme"           → behaviour            → a phase
"the icon file exists and is imported"  → artifact for phase 2 → a phase
"imports tidied up"                     → process              → fold into a neighbour
```

If the only verification you can invent is "it compiled", the phase has no result
of its own and does not deserve to be separate.

### Why *Do not touch* is narrow

The mechanical path check already catches everything outside *Changes*, with no
judgement at all. Repeating it under *Do not touch* duplicates a check that runs
first anyway and makes the field unreadable for a weak model.

Exactly one case is left uncovered: **someone else's region inside a permitted
file.** Phases 3 and 4 both edit `ThemeToggle.tsx` — the path is legal for both,
and the neighbour's handler is off limits. That is the content of the field, and
why it is two or three lines rather than a screen.

Global limits — versions, no new dependencies, the task's out-of-scope — live in
the header only and are not repeated per phase. "Do not introduce a new entity"
does not get its own line either: it is the negative side of a named abstraction
and is written in *How*, in the same sentence as the abstraction.

### Steps bind the implementer, not the reviewer

The implementer's brief is an **imperative**. Not "recommended", not "roughly this
order": a weak model improvises the moment it sees the word "can", and it is not
offered the choice.

The reviewer compares the diff against the **fields**, never the step list. "Did
it in a different order" is not a finding — review by the letter buys a fix round
for nothing, invisibly, because the human is on the loop rather than in it.

The asymmetry works because these are different actors reading different briefs.

The cost of a divergence differs the same way:

```text
divergence touches a field of the phase
→ stop, PLAN_CONFLICT, then the common divergence protocol

divergence touches only a step
→ the implementer adapts and continues
→ the deviation goes into its report, under ## Divergences
→ the orchestrator writes confirmed deviations into the plan
```

Unsure whether a field is touched? Treat it as touched and stop. An error in that
direction costs one visible, cheap stop instead of a silent divergence.

## Topology

Number phases straight through. A unit of dispatch is described as "phases 1–3",
in the artifact and in conversation alike. **Do not introduce a term for a group
of phases** — the range is the name, and every artifact derived from one is named
after it. A separate noun for something the reader can already see is one more
mapping to hold, and the mapping is what goes stale when the boundaries move.

**Verification is not needed after every phase.** Three phases — "add the icon
file", "put the icon in the header", "clicking switches the theme" — where the
first two are checked by grep and deserve no test of their own. The one
meaningful case goes after the third and closes all three.

You **propose** where the boundaries go and which model builds each group; the
human approves and corrects. This is one of the points where a human in the loop
is mandatory.

Two relations, marked by you and approved by the human:

| Relation | Meaning |
|---|---|
| **Sequential** | starts only once the work it depends on has landed as a commit |
| **Parallel** | a group of phases runs at once from one HEAD, and a later phase joins them |

There was a third, *Asynchronous* — start the next unit without waiting for the
intermediate verdict. It was an optimisation on a wait, and the run no longer
takes that wait.

### Parallel is contractual, or it does not happen

**Parallelism is not the goal of splitting.** Make it the goal and phases get cut
to avoid touching shared files, which turns one meaningful checkable phase into
thirty file-disjoint fragments.

Mark phases Parallel only where **all three** of these hold. Two out of three is
Sequential.

1. **The contract between the sides is already frozen** — by an earlier phase's
   *Frozen for later phases*. Both sides build against names, signatures and data
   shapes that neither of them invents, and neither reads the other's code.
2. **Their write-sets do not intersect.** Take the union of the *Changes* fields
   on each side and check that the two unions are disjoint. That is checkable at
   approval, by you and by the human, with no judgement in it.
3. **A later phase joins them.** Name it. Without a join, nothing ever proves the
   two sides meet.

Condition 1 read backwards is the decision procedure, and it decides every case:

```text
the later phase needs the earlier one's CODE   → Sequential
the later phase needs only its SHAPE           → write the shape down,
                                                  and it is Parallel
```

Almost every chain that looks sequential is really the second line. "I do not
know the implementation yet" is not a dependency — it is a missing sentence in
*Frozen for later phases*, and writing that sentence is the whole difference
between two phases that queue and two that run at once. Ask it of every
Sequential pair before you settle: does this phase need what the earlier one
*wrote*, or only the shape it exposes?

The canonical shape:

```text
phase 1  lands the module, and freezes the contract
phase 2  builds one side of it   ┐ parallel — disjoint paths, neither sees the
phase 3  builds the other side   ┘ other's code, both see the contract
phase 4  joins them
```

Disjoint paths are a **precondition**, not a hope. This file used to permit two
phases to edit one file at once — "parallel by purpose, not by file" — and that
permission is exactly where the collisions came from. Where paths intersect, the
phases run Sequential.

Assign the **model per row**. **Sonnet by default; Opus only where the phase is
genuinely hard** — the densest document in the tree, a design the plan could not
fully fix, a phase whose failure mode is quiet. There is nothing below Sonnet:
one fix round costs an implementer pass and a gate pass, which
`dev-skills:implement` calls the largest single cost in the run, and no cheaper
model saves that much. The orchestrator executes the assignment and does not
change it silently.

The `Implementer` column is filled on every row, even when every row says the
same thing. A column that appears only sometimes makes the reader work out the
table's shape before reading it; a column always there is one cell to change.

```markdown
| Phases | Implementer | Why the boundary is here |
|---|---|---|
| 1 | Sonnet | everything downstream builds on this contract |
| 2, 3 | Sonnet | the two sides of that contract, parallel, joined by 4 |
| 4 | Sonnet | the join, and the last work before the gates |
```

The column headings are fixed: the orchestrator reads this table mechanically.

## Dependencies are expressed in the producing phase

If phase 3 relies on an interface from phase 1, that is written **in phase 1** —
and *written* is literal. The field carries the thing itself:

````markdown
**Frozen for later phases**
- `type Config = { retries: number; timeout: number }`
- `loadConfig(path: string): Config` — throws `ConfigError` on a malformed file
````

**The frozen thing is written, not referenced.** "The shape agreed in phase 1",
"the interface from the module above", "the signature does not change" — none of
those freeze anything, because none of them let a later phase write the call. The
test is blunt: could an implementer who has read this field and no code produce a
correct call? If not, the field is a note to yourself.

That is the *Frozen for later phases* field, and the union of those fields is the
**frozen contract** — what a parallel group's two sides build against without
seeing each other's code, and the one thing a review may not change with an
ordinary finding.

The rule doubles as a test of the split: if a constraint cannot be stated locally,
the phases are cut in the wrong place and need regrouping — and that shows up at
plan approval rather than at a fix.

## Final-gate scenarios

The one-off half of the environment contract: what gets clicked through on the
live system. The permanent half — how the project is built and run — lives in
`CLAUDE.md`; see `dev-skills:implement`'s `environment-contract.md`.

**Every scenario is the executable spelling of a test case, and says which one.**
Numbered, concrete, each with its `from:` and its expectation:

```markdown
1. from: TC-1 — Start the app with `mcp.enabled = true`, `transport = "stdio"`.
   Connect an MCP client to the process. Expect: a non-empty tool list, each with
   a name and a schema.
2. from: TC-2 — Restart with `transport = "http"`. Connect with a valid session.
   Expect: the same list.
3. from: TC-5 — Repeat without a token. Expect: 401.
```

A scenario with no `from:` is a requirement nobody approved, and it does not get
driven. Scenarios are not invented here — inventing them is how the runtime gate
ends up checking things the human never agreed were the point.

The list therefore needs no approval of its own: the human already approved the
meaning when they approved the cases. At acceptance it is the checklist they work
through, so they never have to work out what to check.

## Ledger

The run's record and the resume point after a compaction. **One line per row of
the Topology table**, named by its phases, with the tests before them and the two
gates after — so the table above and this list are the same split written twice,
and a boundary that moves in one has an obvious place to move in the other:

```markdown
- [ ] Plan approved
- [ ] Test cases approved
- [ ] Tests written
- [ ] Phase 1
- [ ] Phases 2–3
- [ ] Phase 4
- [ ] Gate A — `HEAD` at the first gate dispatch:
- [ ] Gate B
- [ ] Squash prepared
- [ ] Accepted by the human
- [ ] Integrated
```

The blank on the `Gate A` line is a slot, not a stray colon. The fix-round cap is
counted from that commit — `git log --format=%s <it>..HEAD | grep -c '^fix('` —
and a cap counted from a `HEAD` nobody wrote down is enforced by recollection,
which is how a cap of two once ran to four. The orchestrator fills it in when it
dispatches the first gate; leave it empty.

**One human acceptance, and it sits after the squash.** The human approves
exactly the object that lands on the base, not a range that is afterwards
rewritten into something nobody read. Two separate acceptances — one for
behaviour, one for code — meant the second arrived after the first had already
been spent, and it never bought a second decision.

If the test-case grilling reopened the plan, the round gets its own line:

```markdown
- [ ] Plan re-approved (round 2)
```

An approval that was superseded has to be visible. Without the line the run
carries a plan the Ledger calls approved, in a version nobody approved.

## Verification always exists

Whether the project has test infrastructure is fixed by **the plan**, not
discovered by the implementer. The expected testable scope is part of the plan.

If the project has no tests, a case is still written — as an observation or a
command rather than a test: "grep confirms the file exists and is imported".
Without it, in a project without tests, phases have no check at all short of the
final gate.

**The plan names the cases; the code that checks them is written from them.**
*Verification* carries the case IDs and nothing else. What counts as correct
behaviour is a decision and lives once, in `## Test cases`; the scaffolding —
`describe`, mocks, fixtures, render helpers — is mechanics and follows the
repository's neighbouring tests.

Where red *is* the contract — a bug, or tests as the goal — say in the phase that
the test lands as **its own commit before the implementation**, so the reviewer
can run it there and watch it fail.

## Before you present it

Run the shape check first. It is mechanical, and it costs one command:

```bash
skills/implement/scripts/plan-check <plan file>
```

- **`0`** — the file is well-formed, or `plan-check` repaired it and left nothing
  for anyone to decide. A repair is announced on a `fixed:` line and is never a
  finding; read the line, because the file on disk is now different from the one
  you wrote.
- **`1`** — findings, one per malformed or missing thing, each naming the phase
  it belongs to. Every one of them is yours to fix **in the plan**, here: the
  content of a missing field is a decision, and no actor inside a run may invent
  one, so the same finding met at execution stops the run and goes to the human.
- **`2`** — usage, or the file is not there.

Do not open the script to work out what it wants; the message says. The same
check runs again at preflight when `dev-skills:implement` starts, so nothing left
here is missed — it is found later instead, when the plan is no longer in front
of you and the fix costs a stopped run.

Then read the plan against the epic, or against the conversation if there is no
epic:

1. **Coverage.** Every story points at a phase, and every phase serves a story.
   List anything on either side that does not.
2. **Placeholders.** No "TBD", no "handle edge cases", no "similar to phase N".
3. **Name consistency.** A symbol frozen in phase 1 is spelled the same way in
   phase 4.
4. **Dashes.** `plan-check` proves the seven subheadings are present; only you
   can tell a dash that means "there is no neighbouring conflict" from one that
   means the field was never thought about.
5. **The header lines.** `Norms:` names every document a reviewer is allowed to
   hold the work to. `Baseline:` was measured, not guessed.

Fix what you find inline. For interface shape and seam placement, the vocabulary
is in [codebase-design.md](references/codebase-design.md).

## The gate

Present the plan and take approval before anything is built. Show:

- the user stories;
- the moments, in the person's words — or the dash and why it holds;
- the phase list, one line each;
- the topology: how the phases are grouped, the model on each group, and the
  reason each boundary sits where it does — and for any Parallel group the frozen
  contract, the two disjoint path sets and the join phase;
- the test seams, as their own question;
- the `Norms:` and `Baseline:` lines;
- that `plan-check` exits `0` on this file, and anything it repaired to get
  there;
- anything you settled by your own judgement rather than from the epic.

Then ask:

> **This plan, as written, is what gets built. Approve?**

Not the final-gate scenarios: they are a projection of test cases that do not
exist yet. They come next, and so does the second approval.

## Test cases

Written **after** the plan is approved, in the same session, with the human in
the room. Not drafted silently and handed over to be corrected forever — ask
leading questions and write down the answers. "What should happen if the address
is already taken?" is the shape of it.

The human approves the **meaning** of a case. Test code, mocks and fixtures never
reach them.

**A case is not a test.** "An invalid email cannot register" is a case; the regex
and the wording of the error are mechanics, and they are somebody else's.

Each case carries an ID, the story it serves, preconditions, the action, the
expected behaviour, a starting state, and a `gate-b:` label:

```markdown
- **TC-3** · US-2 · gate-b: browser
  - given: a signed-out visitor on `/signup`
  - when: they submit `alice@` and a valid password
  - then: the form stays, the field is marked, and what they typed is still there
  - initial state: RED
```

A case serving no story is either a missing story or a case nobody asked for —
resolve it, do not leave it. The starting state is `RED`, `GREEN` or
`NOT-YET-RUNNABLE`; `GREEN` is a real answer, because a case that already holds
is how a regression becomes visible later.

### What the `gate-b:` label decides

`browser`, `snapshot`, `simulator`, `http`, or `N/A`.

**Whatever is not in the test cases is not checked on the running system.** The
label is what makes that rule mechanical rather than aspirational: the runtime
gate is handed exactly the cases whose label is not `N/A`, and writes one piece
of evidence per case. A case with no file was not checked. Not written down means
not tested.

**Zero executable cases stops the run here.** A plan whose outcome cannot be
observed on a running system has not said how anyone would know it worked, and
finding that out after the code is built costs the whole build. The stop is
lifted only by the human saying, explicitly, that `N/A` everywhere is right for
this work. It is never lifted by silence.

Then write the final-gate scenarios as the projection of the executable cases,
and take the second approval:

> **These cases are what gets checked, and nothing else is. Approve?**

### When the grilling opens a hole

Working through the cases sometimes exposes something the phases cannot express —
an architectural gap, a seam in the wrong place, a story nobody had written down.
That voids the first approval. Present the plan whole again rather than patching
it quietly, and add the round to the Ledger.

A quiet second version of an approved plan is worse than a visible re-approval:
the human believes they are watching a plan they read.

## Handoff

Once both approvals are in, stop. The human invokes `dev-skills:implement`; it
creates the workspace, runs preflight, and executes. Do not create a branch or a
worktree here.

## What is not in a plan

- product decisions — they are in the epic, and the plan does not reopen them;
- function bodies, test code, imports and style — typing, not decisions;
- commit text — derived from the Goal at finish;
- the other plans in the epic's list — each is planned when the human names it.
