---
name: epic
description: Use when the work is too big for one plan and needs splitting first — "this is a whole epic", "write the epic", "break this into plans", "one plan won't cover it". Writes the epic that holds the shared decisions, the vocabulary, and the list of plans the work breaks into.
---

# Writing an epic

An epic is the document that holds a system whole **when it has to be broken
into several plans**. It carries what those plans share: the decisions they all
follow, the vocabulary they all use, and the list of plans with the dependencies
between them.

**Announce at start:** "Using dev-skills:epic to write the epic for this work."

## When there is no epic

One plan means no epic. The plan's header already carries the outcome, the
constraints, the out-of-scope list and what the final gate proves.

The trigger is not size. It is **whether the work produces more than one plan**.

The human decides. You may say what you see: "this is large enough that either
half of it leaves the scope, or we fix it with an epic and split it." Then wait.

## What goes in

Write it to `.ai-workflow/epics/YYYY-MM-DD-<topic>.md`. See *Storage* below.

**Goal.** What the system should be able to do, in one paragraph.

**Result from the user's side.** What the person using it does, and sees, in
their own terms. Not components — behaviour.

**Constraints.** What is fixed for every plan below: transports, dependency
limits, version floors, mechanisms that must be reused rather than replaced.

**Out of scope.** What this body of work does not include. Name the things a
reader would reasonably assume were included.

**Decisions taken.** The heart of the document: decisions common to all the
plans, each with the reason that settled it. Every plan is bound by them and
**no plan reopens them**. This is the section that makes the epic worth writing
— it is what stops plan 3 from quietly contradicting plan 1, which nobody would
notice until integration.

**Glossary.** The terms already carried into `docs/CONTEXT.md` that every plan must
use identically. Names only; the definitions live in `docs/CONTEXT.md`.

**Integration invariants.** What has to stay true where two plans meet — an
ordering, a shape passed between them, a state neither may leave behind. Each
plan is verified on its own; these are the claims no single plan's verification
can reach.

**Plans.** A list, not a backlog — see below.

**ADR candidate**, if one arose. A proposal, never an action: name the decision
and the trade-off, and say it is worth recording. Writing it is the human's
call, and it happens through `dev-skills:domain-modeling`.

**What is not in this epic.** An explicit section: no file paths, no signatures,
no code, no phases, no checkboxes, no implementation order, no estimates, no
instructions to an implementer. All of that belongs to a plan. The epic outlives
changes to the code; a plan is stale after the merge it describes. That is why
they are separate documents, and this section is how the separation stays real.

**And no user stories, and no test cases.** They belong to a plan, and they are
not duplicated here. An epic exists only when the work needs more than one plan;
a story that lived at this level would have nowhere to live at all in the
single-plan case, which is most cases. Each plan carries its own stories, grills
its own cases out of the human, and is the only owner of both.

## The list of plans

```markdown
| # | Plan | State | Depends on |
|---|---|---|---|
| 1 | Transport and tool registration | ready to plan | — |
| 2 | First tool over the service layer | — | 1 |
| 3 | Call log and access revocation | — | 1 |
| 4 | Settings UI | — | 1, 3 |
```

An entry is **a line in this epic, not an artifact**. It becomes a plan only
when the human names it and invokes `dev-skills:plan`. Nothing is created ahead of time,
nothing has to be maintained, and the whole list dies with the epic.

This is what separates it from a ticket layer: tickets were files with their own
contract, created in advance, and they outlived their usefulness by default.

**Two actors move the State column, and only two:** `dev-skills:plan` sets *in progress*
when it creates the plan, `dev-skills:finish` sets *done* after integration is proven.
Everything else in the epic is edited by the human.

The split is not doctrine. If planning reveals that 2 and 3 fit in one cycle,
they merge — the list is corrected, not defended.

## Sizing an entry

Each entry must be coverable by **one plan** and end in a state someone can
check. "Add MCP to the app" is an epic; "tooling", "backend", "UI" are entries.

The split is not fixed in advance. A small tool may let backend and UI share one
plan; a full backend service is planned and verified on its own, and only then
is the UI planned.

Do not introduce a level between epic and plan.

## When the epic arrives late

The second plan is often not visible until the first one is approved, or built.
The answer is not to write epics pre-emptively — most tasks produce one plan, and
the epic would be overhead nobody reads. The answer is to have a route for the
day the second plan appears.

On that day:

1. **Create the epic**, as above.
2. **Register the existing plan** as entry 1, in whatever state it is actually
   in.
3. **Move** the decisions it holds that now bind the second plan too — out of the
   plan, into *Decisions taken*.
4. Leave a dated pointer where they used to be:

```markdown
Epic: .ai-workflow/epics/2026-08-04-mcp.md — decisions moved 2026-08-04
```

**Move, never copy.** Two owners of one decision is exactly the failure this
document exists to prevent. A plan is edited during execution and an epic is
not, so by plan 3 the two copies disagree and nobody can say which is current. A
copy is not a safety net; it is a second version.

**The first plan's stories and test cases do not move, and are not
re-approved.** They were approved for that plan, they still describe it, and
taking them up here would strip the one document that has to carry them. Only
shared decisions rise.

## Storage

`.ai-workflow/` inside the repository. Outside it, these become system litter you
forget about; inside, they die with the repository.

Before the first write, make sure the repository ignores the directory:

```bash
grep -qxF '.ai-workflow' .gitignore || printf '.ai-workflow\n' >> .gitignore
```

**Without a trailing slash.** A pattern with one matches directories only, and
in a worktree `.ai-workflow` is a symlink, which git sees as a file. Do not
analyse what other variants are already there — if the exact line is absent, add
it.

## After the epic

Present it and take approval. Then stop.

The next step is the human's to call: they name an entry from the list, and
`dev-skills:plan` starts from it. Do not begin planning entry 1 because it is obviously
first.
