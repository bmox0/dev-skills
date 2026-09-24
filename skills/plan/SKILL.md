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
| **Test cases** | what gets checked — and nothing outside it is; the join names the ones it proves | tester, both gates |
| **Topology** | the rows the joins induce, and why each boundary sits where it does | orchestrator |
| **Graph** | the picture of what waits on what, rendered from the phases' `Depends on` fields | the human at approval |
| **Phases** | bounded units of execution, nine fields each; a join is one of them | implementer, reviewer |
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
## Graph
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

The strings the scripts anchor on — the nine field names, the two *Verification*
grammars, the artifact names derived from a phase range — are written out once, in
[`references/VOCABULARY.md`](../../references/VOCABULARY.md), together with the
vocabulary every artifact in a run uses. The skeleton is the shape; that file is
the letter. Neither is a copy of the other.

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

**Fixed in prose:** every other decision — every path touched, and on a **join**
the test paths it may repair, which an ordinary phase never has; the
abstractions used, by name and with their path; the join that proves the phase,
as `- proved by: phase <n>`; edge cases and the behaviour on them; what counts
as an error and how it shows; what not to touch and what not to introduce;
order, where order carries meaning.

**Never appears:** function bodies, test code, imports, style. That is typing,
not deciding. The planner saves nothing by omitting it, because the planner
should not be writing it at all.

**Sufficiency test:** two competent engineers reading this phase should write
functionally identical code. If they would differ in something that would have to
be redone, a decision is missing — add it. If they differ only in form, the
reviewer closes that against the repository's conventions.

Do not economise on density. A thin plan is paid for twice: once in a bad
decision, and again in the rework.

### The nine fields

The subheadings are **fixed strings**. This is not formatting: the orchestrator
cuts a phase into a brief mechanically, and mechanical assembly needs stable
anchors.

| Field | What it carries |
|---|---|
| **Becomes true** | the observable result of the phase; it also sets the phase's size |
| **Changes** | paths *and* entities: a symbol, a function, a region — not only a file |
| **Depends on** | the earlier phases whose files this phase edits — never a shape, never an ordering preference |
| **Implementer** | the model that builds this phase: Sonnet, or Opus where the phase is genuinely hard |
| **How** | named abstractions with paths, plus the negative side: what not to introduce |
| **Do not touch** | only conflicts *inside* paths already granted |
| **Frozen for later phases** | the names, signatures and data shapes later phases build on — written out, never referred to |
| **Verification** | the join that proves this phase — or, on the join itself, the range it joins and the cases it proves |
| **Steps** | the order of work, with checkboxes |

**All nine are mandatory; absence is written as a dash.** `Do not touch: —` means
"there is no neighbouring conflict", not "I forgot to think about it". There is no
other way to tell forgetfulness from a considered nothing, and in *Frozen for
later phases* that slip costs the next phase range a stop. The presence of all
nine subheadings is checked by grep, with no model judgement involved.

*Implementer* is the one field with no dash form: every phase is built by
something, so it holds `- Sonnet` or `- Opus`, alone or with its reason after an
em dash.

In a typical phase four of the nine are dashes. That is cheaper than one
invisible omission.

**A phase whose *Changes* names a script under `skills/*/scripts/` also names
that script's mutation patches**, because editing the script is what makes them
stale.

*Verification* is written in one of exactly two grammars, and `plan-check`
refuses anything else. On an ordinary phase — one bullet, naming the join, no
trailing prose:

````markdown
**Verification**
- proved by: phase 9
````

On the join itself — the range it joins and the cases it proves, the range always
a two-number span and never a bare number:

````markdown
**Verification**
- joins: phases 1-8
- cases: TC-1, TC-2, TC-3
````

`- cases: —` alone is the join asserting it proves no approved case, the same way
a dash asserts in every other field. A phase carrying `- joins:` **is** the join:
there is no other marker, no heading suffix and no Topology column for it.

Beside *Verification* sits the **Phase Check** — the one command a phase runs on
its own work, named by the environment contract rather than by you: a formatter,
or none. A phase compiles nothing, tests nothing and lints nothing, which is why
its result is not proved until its join — and why *Verification* names that join
rather than a check the phase could have run itself.

### The form

````markdown
### Phase 3. Pressing the button switches the theme

**Becomes true**
- clicking the button toggles the theme between `light` and `dark`
- the chosen value survives a page reload

**Changes**
- `src/features/theme/ThemeToggle.tsx` — the `onClick` handler

**Depends on**
- —

**Implementer**
- Sonnet

**How**
- use the existing `useTheme` (`src/shared/theme/useTheme.ts`); it already holds
  `setTheme` and persists to `localStorage`
- do not introduce a new store or context

**Do not touch**
- the button's markup in `ThemeToggle.tsx` — it belongs to phase 2

**Frozen for later phases**
- —

**Verification**
- proved by: phase 4

**Steps**
- [ ] wire `useTheme` into `ThemeToggle`
- [ ] hang the toggle on `onClick`
````

And the join those phases name, written with the same nine fields and nothing
extra:

````markdown
### Phase 4. The theme toggle works end to end

**Becomes true**
- phases 1–3 compile together, their tests run, and what did not meet is repaired

**Changes**
- `src/shared/theme/useTheme.ts`, `src/features/theme/ThemeToggle.tsx` — the
  union of phases 1–3's write-sets
- `src/features/theme/theme.test.tsx` — mechanics only

**Depends on**
- phase 1 — `useTheme`
- phase 2 — the button's markup
- phase 3 — the `onClick` handler

**Implementer**
- Opus — the join is the most expensive seat in the run

**How**
- merge the tester's branch first, then compile the range, then run
- repair a test's mechanics — a spy's placement, a timeout, the order of a render
  — and never what it asserts
- no adapter for a frozen name: a frozen name that has to change is a
  `PLAN_CONFLICT`

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- joins: phases 1-3
- cases: TC-4, TC-5, TC-6, TC-7

**Steps**
- [ ] merge the tester's branch
- [ ] compile the range, then run its tests and its checks
- [ ] repair what did not meet, and record each repair
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

**A case is not needed after every phase.** Three phases — "add the icon file",
"put the icon in the header", "clicking switches the theme" — where the first two
are checked by grep and deserve no case of their own. The one meaningful case
belongs to the join that covers all three. The *Verification* field is still
written on all three, because all three name that join.

**You do not choose the rows.** ADR-0005 settled it: the join is the only
barrier, and everything between two joins dispatches at once. So the rows are
read off the joins — every phase between two joins shares one row, every join
stands alone in its own — and `plan-check` refuses a table that says otherwise.
What you propose, and the human approves, is **where the joins go**; the table
follows from that with nothing left to decide.

This matters because the instinct it replaces is expensive. Left to judgement,
a boundary appears wherever a phase produces something a later phase consumes —
and that is almost every pair of phases, so the plan queues work that had no
reason to wait. The barrier you did not write is the width you did not lose.

| Relation | Meaning |
|---|---|
| **Parallel** | every phase of the row is dispatched at once, all from one base, and the join after it joins them |
| **The join** | its own row, dispatched alone: the one place the row's phases have to meet |

There was a third, *Asynchronous* — start the next unit without waiting for the
intermediate verdict. It was an optimisation on a wait, and the run no longer
takes that wait. *Sequential* went the same way: it named a barrier the model
does not have.

A row's **width** is the number of phases it dispatches at once. Width needs no
column of its own: a row's phases run at once unless one of them declares a
`Depends on` naming a sibling in the same row, in which case the row is one
dispatch, built in order by one implementer. `Depends on` is validated by
`plan-check` already, so the information is in the plan and it is checked.
Narrowing a row further is the orchestrator's to do, recorded with its reason
under `## Corrections during execution` and never done quietly. **Do not add a
third Topology column**: the two headings are fixed, and `dispatch` refuses a
table carrying any other. The model used to be the third, and it moved to the
phase — a phase is hard or not on its own merits, whichever band it lands in.

A row is named by its range, `<a>-<b>`, or by a bare number when it carries one
phase. That spelling is the one `plan-check` reads.

### Parallel is contractual, or it does not happen

**Parallelism is not the goal of splitting.** Make it the goal and phases get cut
to avoid touching shared files, which turns one meaningful checkable phase into
thirty file-disjoint fragments.

Phases share a row by construction, so these are not a permission you grant —
they are three things that must be true of every row, and a plan where one of
them fails is wrong before it runs.

1. **The contract between the sides is frozen in the plan** — written out in a
   *Frozen for later phases* field, which is a field of the document and not an
   artifact of a run. Both sides build against names, signatures and data shapes
   that neither of them invents, and neither reads the other's code. The phase
   that will create the module does not have to run first: the sentence is there
   at approval, and that is what the other side builds against.
2. **Their write-sets do not intersect.** Take the union of the *Changes* fields
   on each side and check that the two unions are disjoint. That is checkable at
   approval, by you and by the human, with no judgement in it.
3. **A later phase joins them.** Naming it is not loose prose: every phase of the
   row names it in its own *Verification*, as `- proved by: phase <n>`, and the
   join names the range back, as `- joins: phases <a>-<b>`. `plan-check` checks
   that the range covers every phase that points at it, so the claim is read off
   the fields rather than asserted. Without a join, nothing ever proves the two
   sides meet.

Condition 1 read backwards is the decision procedure, and it decides every case:

```text
the later phase needs the earlier one's CODE   → same row, one dispatch,
                                                  built in order by one
                                                  implementer — a Depends on
the later phase needs only its SHAPE           → write the shape down,
                                                  and the row runs wide
```

Neither answer is a barrier. A barrier is a join, and nothing else.

Almost every chain that looks sequential is really the second line. "I do not
know the implementation yet" is not a dependency — it is a missing sentence in
*Frozen for later phases*, and writing that sentence is the whole difference
between two phases that queue and two that run at once. Ask it of every pair
that feels ordered before you settle: does this phase need what the earlier one
*wrote*, or only the shape it exposes?

The canonical shape — and note where the row ends, because the instinct is to
end it one line higher:

```text
phase 1  lands the module, freezing the contract   ┐ one row. The plan carries
phase 2  builds one side of it                     │ the contract, so nobody
phase 3  builds the other side                     ┘ waits for the file
phase 4  joins them                                  the row's one barrier
```

Phase 2 writing `import { loadConfig } from "./config"` before phase 1 has
created `config.ts` is not a race and not a gamble — it is the model working.
The file arrives when the row merges, and the join is where the import first has
to resolve.

Disjoint paths are a **precondition**, not a hope. This file used to permit two
phases to edit one file at once — "parallel by purpose, not by file" — and that
permission is exactly where the collisions came from. Where paths intersect, the
phases share one dispatch and are built in order — still one row, still no
barrier.

Assign the **model per phase**, in that phase's *Implementer* field. **Sonnet by
default; Opus only where the phase is genuinely hard** — the densest document in
the tree, a design the plan could not fully fix, a phase whose failure mode is
quiet. There is nothing below Sonnet: one fix round costs an implementer pass
and a gate pass, which `dev-skills:implement` calls the largest single cost in
the run, and no cheaper model saves that much. The orchestrator executes the
assignment and does not change it silently.

It sits on the phase and not on the row because a phase is hard, or not, on its
own merits — and the rows are no longer yours to draw, so a model on the row
would be a property attached to whichever band the phase happened to land in.
Put the reason after an em dash whenever the answer is Opus; `- Sonnet` alone
needs none.

```markdown
**Implementer**
- Opus — the densest file in the tree, and its failure mode is silent
```

A row may hold phases that disagree, and `dispatch` refuses to build them as one
unit when they do. That is a real refusal, not a nuisance: it means the row was
about to be handed to one implementer under two answers.

The table itself carries only the split and its reason:

```markdown
| Phases | Why the boundary is here |
|---|---|
| 1-3 | the module and the two sides of its contract, joined by 4 |
| 4 | the join, and the last work before the gates |
```

The column headings are fixed: the orchestrator reads this table mechanically.

### The join

A **join** compiles the phases before it, merges the tester's branch, runs the
tests and the checks, and repairs what did not meet. It is the only place before
the gates where anything is verified.

**It is a phase.** The same nine fields, written by you and never computed by a
script, with its own row in the Topology table, dispatched with the same
`dispatch <plan> <n>` as any other phase. It is not a mode, a marker or a fourth
column — a phase whose *Verification* carries `- joins:` is the join, and that
bullet is the whole declaration.

**Its *Changes* is the union of the write-sets of the range it joins**, plus the
test paths it may repair. That is not bookkeeping: one
`preflight --attribution <plan> <a>-<n> <BASE> <branch>` over the inclusive range
is what checks the join, and it checks against exactly what this field declares.
So the test seams have to appear there too, or the repair the join is there to
make lands outside its own declaration.

**Its *How* carries the negative half.** No adapter for a frozen name, ever — not
a re-export, not a wrapper, not a rename at the call site. A frozen name that has
to change is a `PLAN_CONFLICT`, because the whole row was built against it and
two phases already wrote it down.

**It repairs a test's mechanics and never its intent.** A spy's placement, a
timeout, the order of a render — those are the join's. What a test asserts is the
approved case, and the case belongs to the plan. Two identical implementations of
one thing arriving from two phases of one row are mechanics: the join collapses
them and records it. Two *different* approaches to one thing are intent, and that
is a `PLAN_CONFLICT` rather than something to reconcile.

**Two repairs and it goes to the human**, counted the way the judge's cap is —
from the base recorded on its Ledger line, `git log --format=%s <it>..HEAD |
grep -c '^fix('`. A join that is still red after two attempts is a plan defect,
and a plan defect is not something an implementer may fix.

**Size it deliberately.** The join is the most expensive seat in the run:
every phase before it is cheap precisely because it compiles nothing. The width
of the row it joins multiplies the cost of a wrong contract, so a wide row with a
thin *Frozen for later phases* is paid for here, at the one point in the run
where the bill arrives all at once.

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

**The completeness bar is a compiling import.** The frozen contract is what a
later phase can write a compiling import against — module paths and exported
names, not only types. A phase builds against modules that are not in the tree
yet, and writes the import for one anyway; it does not go looking for the module
and it does not create it. A path you leave out is therefore not a gap the
implementer closes by inventing one — it is a stop, and it arrives at width,
multiplied by every phase of the row.

The rule doubles as a test of the split: if a constraint cannot be stated locally,
the phases are cut in the wrong place and need regrouping — and that shows up at
plan approval rather than at a fix.

### A dependency is a file, not a shape

A **dependency** is one phase needing another's *file* in order to edit it.
Needing its *shape* is not a dependency — the shape is written out in *Frozen
for later phases*, and code is written against it before the file exists.

Declare it in the depending phase's own **Depends on** field, in the one
grammar `plan-check` enforces: `- phase <n> — <why this phase needs its file>`
for each phase whose file it edits, or `- —` alone when it edits no earlier
phase's file. `<n>` is always lower than the phase carrying the bullet, so the
graph is acyclic by construction and `plan-check` needs no cycle detector.

The dash is an assertion, the same way a dash in any other field is: `- —` says
there is no dependency, not that nobody thought about it.

**This field does not draw the rows.** The rows come from the joins; `Depends on`
says which earlier phase's *file* this one edits. Needing that file never pushes
a phase into a later row — it makes its row a single dispatch, built in order by
one implementer, because a phase compiles nothing, there is no green build to
wait on, and the join is where anything is proved. Write both: the row in the
table, the bullet in the phase.

`plan-graph` renders the plan's picture from those fields, so the picture is
never drawn by hand and never edited by hand once written — written by
`plan-graph`, edited by nobody:

````markdown
## Graph

<!-- rendered by skills/implement/scripts/plan-graph — do not edit by hand -->

```text
1  --  The anchors are named in the shipped vocabulary
2  --  A malformed `Depends on` is refused before approval
3  --  `plan-graph` renders the picture from the fields
4  --  The planner and the implementer are told what the field is

4 phases · 4 with no dependency · longest chain: 1
```
````

Everything between `## Graph` and the next heading is regenerated, so nothing
hand-written survives there — commentary on the picture goes above the heading.

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
the Topology table**, named by its phases, with each join's tests before the
range they cover and the judge after — so the table above and this list are the
same split written twice, and a boundary that moves in one has an obvious place
to move in the other:

```markdown
- [ ] Plan approved
- [ ] Test cases approved
- [ ] Tests for phases 1–3 written
- [ ] Phase 1
- [ ] Phases 2–3
- [ ] Phase 4 — the join; base at dispatch:
- [ ] Judge — `HEAD` at dispatch:
- [ ] Squash prepared
- [ ] Accepted by the human
- [ ] Integrated
```

The tests line is the tester's, one per join and named by the range that join
covers, because that is the granularity the tester is dispatched at.

The blank on the `Judge` line is a slot, not a stray colon. The fix-round cap is
counted from that commit — `git log --format=%s <it>..HEAD | grep -c '^fix('` —
and a cap counted from a `HEAD` nobody wrote down is enforced by recollection,
which is how a cap of two once ran to four. The orchestrator fills it in from
the `cap origin:` line `dispatch --judge` prints, and the judge counts from it;
leave it empty.

The blank on each join's line is the same slot for the same reason: the join's
two-repair cap is counted from the commit it was dispatched at, by the same
`grep -c '^fix('`, and an uncounted cap is the one that runs to four.

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
Without it, in a project without tests, the join has nothing to run and nothing
between plan approval and the final gate checks the work at all.

**The cases live once, in `## Test cases`.** The join names the ones it proves;
an ordinary phase names only the join. That is the whole division: what counts as
correct behaviour is a decision and it is written in one place, while the
scaffolding — `describe`, mocks, fixtures, render helpers — is mechanics and
follows the repository's neighbouring tests.

**Phases write no tests.** The tester writes them, once, at the granularity of a
join, against the frozen contract, on a branch of its own that the join merges.
So no ordinary phase's *Changes* carries a test path and no ordinary phase's
*Steps* takes a case green — only the join's does, for the mechanics it is
allowed to repair.

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

Then render the graph. `plan-check` first, always: `plan-graph` refuses a plan
it cannot trust, and says so by naming `plan-check`.

```bash
skills/implement/scripts/plan-graph <plan file>
```

Its one line of output says which happened:

- **`wrote:`** — the `## Graph` section was stale or missing, and has been
  rewritten.
- **`unchanged:`** — the picture already matched the fields.

Then read the plan against the epic, or against the conversation if there is no
epic:

1. **Coverage.** Every story points at a phase, and every phase serves a story.
   List anything on either side that does not. Every phase also names a join, and
   every join covers what names it — `plan-check` says so, and a plan that does
   not exit `0` is not presented.
2. **Placeholders.** No "TBD", no "handle edge cases", no "similar to phase N".
3. **Name consistency.** A symbol frozen in phase 1 is spelled the same way in
   phase 4.
4. **Dashes.** `plan-check` proves the nine subheadings are present; only you
   can tell a dash that means "there is no neighbouring conflict" from one that
   means the field was never thought about. *Verification* has one of its own: a
   join's `- cases: —` asserts that this join proves no approved case, which is a
   real answer and a rare one — read it twice before you leave it.
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
- the joins: which phase joins which range, and the write-set each one takes on —
  the most expensive seat in the run, shown as such;
- the graph, as rendered, and what it says about which phases wait on nothing;
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

**The second approval exists because of the joins.** A case is scoped to what a
consumer of a **join's** assembled result observes — never to a method, and never
to one phase's internals. Cases at that scope cannot be written until the joins
are known, and the joins are settled by the plan body. So the body is approved
first and the cases second, in that order, for that reason.

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

**The case line gains no `join:` field.** Which join proves which case is written
once, in that join's own *Verification*, and a second copy here is a mapping that
goes stale the first time a boundary moves.

### What the `gate-b:` label decides

`browser`, `snapshot`, `simulator`, `http`, `cli`, or `N/A`. `cli` is a runtime
driven from a shell, where the evidence is the command and what it printed.

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
