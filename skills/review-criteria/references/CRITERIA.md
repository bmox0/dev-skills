# Review criteria

The standard every code review in this workflow judges against. Three seats read
this file, and nothing else defines what a finding is:

| Seat | Where its scope comes from |
|---|---|
| `dev-skills:gate-a` | the plan — the **fields** of every phase, over the whole `BASE..HEAD` |
| `dev-skills:gate-b` | the plan's executable test cases, driven on a running system |
| `dev-skills:review` | whatever the human pointed at — a PR, a file, a tree |

One file, so sharpening the standard sharpens all three at once and none of them
can drift from the others.

## The producible-source rule

**A finding cites its source.** One of four:

- a norm, and the norms ladder below says which sources count as one;
- a requirement of the phase under review;
- a constraint from the plan's header;
- a smell from the baseline below.

Cannot show the source? It is not a finding, and it is not written down.

> "I don't like this name" does not pass.
> "The ADR the plan names under `Norms:` puts handlers of this kind in `hooks/`;
> this one is inside the component" passes.

The rule exists because correctness is settled before any code is read — the
reviewer runs the checks first — so what remains is the territory of taste, and
the search for smells has no natural floor. Without a source requirement,
"green means no remarks" buys a fix round for nothing, and buys it invisibly:
the human is *on* the loop, not in it, and never sees the round that was not
worth running.

## Two classes of finding, and what each one costs

Classify by **consequence**, never by how you arrived at it. A mechanical
comparison and a judgement call can both land in either class.

**`BLOCKER`** — a failed check or a failed test case, a `PLAN_CONFLICT`, or a
violation of a user story, of security, of data integrity, or of a norm the plan
made mandatory on its `Norms:` line. It goes back to the implementer.

**`ADVISORY`** — maintainability and preference, with no contract violation
demonstrated. Cited like any other finding, and written down like any other.

**An `ADVISORY` never opens a fix round.** It travels to the human alongside the
diff, counted on one line. This is the single largest saving in the loop, and it
is deliberate: on a measured run, two fix rounds cost an hour and a quarter
against thirty-seven minutes of implementation, and neither finding that bought
them was blocking. An advisory costs the human one reading. A fix round costs an
implementer pass and a gate pass. Only a `BLOCKER` is worth that.

**Observation** — not a finding at all. Recorded, never blocking, never counted,
never extends a loop. Anything true but outside this review's scope lands here,
and so does everything the third rung of the norms ladder catches.

There is no third class of finding.

## Judge the fields, not the steps

The plan binds the implementer with an ordered list of steps. It does **not**
bind the reviewer with one.

Compare the diff against the phase's fields — *becomes true*, *changes*, *how*,
*do not touch*, *frozen for later phases*, *verification*. "Did it in a different
order" is not a finding. So is "did it in fewer steps", and "combined two steps".
Review by the step list and the review degenerates into letter-matching, which
buys a fix round for nothing.

## Paths are checked first, mechanically

Before any code is read: `git diff --name-only` against the union of the
*changes* fields of the phases under review. A file outside that union is a
finding immediately.

This runs first because going out of bounds is improvisation in observable form,
and catching it needs no judgement at all — two lists, compared. It is the only
defence against a weak model that rests on nothing but git, so it is never taken
from a report: the actor it defends against is the actor that wrote the report.

Then the checks — tests, lint, typecheck, build. Red goes straight back to the
implementer; the code is not read. Debugging stack traces and build noise is not
the reviewer's work, and hunting smells in a tree whose tests fail is wasted.

**Red the plan predicted is not red the run caused.** Where the plan carries a
`Baseline:` line, it says what these commands produced before any work started —
inherited errors, a build that was already broken, a failing test committed on
purpose. Judge the delta. No `Baseline:` line asserts everything was green
beforehand, and then any red belongs to the run.

## Tests are part of the diff

The plan names the cases; the implementer writes the test code. Because a weak
model writes it, the tests are reviewed like any other code, and two findings
are always available:

- **the test does not cover a case the phase declared** — cite the case;
- **the test masks the defect** — it passes on an implementation that is wrong,
  asserts on a mock rather than on behaviour, or computes its expectation with
  the code under test.

A test that could only fail through a crash, a missing selector, or the removal
of the mock itself is not a test. So is one that fires on every intentional
change and sleeps through accidental ones.

## The smell baseline

Fowler's smells (*Refactoring*, ch. 3). They apply even where a repository
documents nothing — which is what makes this a baseline rather than a standard.

Two rules bind every use. **The repository overrides:** a documented standard
always wins, and where it endorses what the baseline would flag, the smell is
suppressed. **Every entry is a judgement call** — "possible Feature Envy", never
a violation. Skip anything tooling already enforces.

One list, for every seat. This file used to split it — smells visible inside one
diff, smells visible only once the pieces were assembled — and that was a split
by phase range, written when a reviewer held only part of the run and could be
told which half to skip. Whether an entry is visible is a fact about how much of the work the
seat holds, not a fact about the smell. Judge what you can see.

- **Mysterious Name** — a name that does not reveal what it does or holds. → rename; if no honest name comes, the design is murky.
- **Primitive Obsession** — a primitive standing in for a domain concept. → give the concept its own small type.
- **Data Clumps** — the same few fields keep travelling together. → bundle them into one type.
- **Feature Envy** — a method reaching into another object's data more than its own. → move it onto the data it envies.
- **Repeated Switches** — the same cascade on the same type recurs. → polymorphism, or one shared map.
- **Message Chains** — a long `a.b().c().d()` the caller should not depend on. → hide the walk.
- **Middle Man** — a unit that mostly delegates onward. → cut it.
- **Refused Bequest** — a subclass ignoring most of what it inherits. → composition.
- **Speculative Generality** — abstraction for a need the plan does not have. → delete it.
- **Duplicated Code** — the same logic shape in more than one place.
- **Shotgun Surgery** — one logical change forcing scattered edits.
- **Divergent Change** — one module edited for several unrelated reasons.

Duplicated Code is worth a deliberate look wherever two cold implementers built
adjacent things without either having seen the other's code. That is the case
that produces it, and neither of them could have noticed.

## Where a norm comes from — the ladder

Rank the sources and stop at the first one that answers. Judge only the part
decidable from the diff in hand: naming, import style, error handling, layout.

1. **Approved documents** — an ADR, `docs/CONTEXT.md`, a coding standard — but only
   the paths the plan lists on its `Norms:` header line. What is not listed, you
   do not go looking for; the planner owns that line's completeness, not you.
2. **Precedents and prohibitions the plan names itself** — the negative half of a
   phase's *how* field, the "use this, not that".
3. **Everything else.** A pattern merely existing in the code is not a norm. Say
   what you saw as an `Observation` and move on.

The third rung is the point of the ladder. The rule it replaces ended "everything
else needs an existing pattern in the code to point at", which turned age into
authority: a reviewer could bless a legacy pattern by pointing at the legacy. A
real defect shipped that way, and shipped predictably — the implementer copied
the oldest thing it found, and the review had nothing to say against it.

A tier-1 document and a tier-2 instruction that contradict each other is a
blocking `PLAN_CONFLICT`. Do not quietly pick the one you prefer.

**Do not compute a norm.** "The newer pattern", "the more widespread pattern" —
each needs a repository sweep and git archaeology, and no reviewer here has that
budget. If it is not on the ladder, it is not a norm.

**When the plan carries no `Norms:` line, this ladder does not apply.** The older
rule stands instead: read what the repository says about how its code is written —
`CLAUDE.md`, `CONTRIBUTING.md`, `CODING_STANDARDS.md`, `docs/CONTEXT.md` for
vocabulary — documented conventions are hard because they cite themselves, and
everything else needs an existing pattern in the code to point at. A plan written
before the header line existed gets reviewed at today's strictness. Without this,
the ladder would make those plans *easier* to pass than they are now.

## What is never a finding

- **A different order, or fewer steps.** The steps bind the implementer only.
- **Anything the plan mandates.** A plan requirement that looks like a defect is
  a `PLAN_CONFLICT`, not a finding: it stops and goes to the orchestrator, who
  takes it to the human. Do not quietly overrule the plan, and do not quietly
  swallow the defect because the plan asked for it.
- **A decision an earlier round already closed.** Accepted work is not reopened;
  the reviewer confirms the related phases were checked and moves on. An
  `ADVISORY` you raised once and nobody acted on does not become a `BLOCKER` by
  being raised again.
- **Anything tooling enforces.** Formatting a linter fixes is not review.
- **A norm the ladder does not reach.** Style no approved document states and no
  plan names. That is the producible-source rule, and it is the most common way
  this review goes wrong.

## What a stated rationale is worth

Nothing. "Left it deliberately", "kept it simple per YAGNI" — that is the author
grading their own work. Judge the code. The rationale belongs in the
conversation about the finding, not in the decision whether to raise it.

## The frozen contract

A review **never changes a frozen contract** through an ordinary finding. That
contract is the union of the *frozen for later phases* fields: the names,
signatures and data shapes later phases were told to build on.

Needing one of them changed is a `PLAN_CONFLICT` — it stops and escalates. It is
not a finding, because a later phase has already been briefed against it, and a
review that quietly renames it leaves the next implementer looking for an
abstraction that no longer exists. In a parallel group it is worse than that:
both sides built against the frozen names without ever seeing each other's code,
so the contract is the only thing that made the group safe to run at all.

Only what is explicitly named in those fields is frozen. Everything else is
ordinary territory — otherwise this rule would stop being a guard on the
contract and start being a ban on findings.
