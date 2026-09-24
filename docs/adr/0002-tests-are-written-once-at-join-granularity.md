---
status: proposed
supersedes: the earlier decision that each phase writes its own tests and the test-writer seat is removed
---

# Tests are written once, by a tester, at the granularity of a join

One measured run produced two test failures of opposite kinds. An independently
written test bent the production code to its own mechanics — `CardDetail` was
made to call `useStore().dispatch()` instead of the frozen `useDispatch()` hook,
because the test installed its spy after render. And an independently written
test was vacuous: `undo.test.ts:97` stayed green against a store whose `dispatch`
did nothing.

A previous session read those as an argument against a separate test-writing seat
and moved tests into the phase. That was the wrong diagnosis. Both failures are
about **granularity** — a test reaching into one phase's internals — not about
who held the pen. A test of the assembled surface touches neither place, and a
phase that writes tests it cannot run has every incentive to fix forward against
them.

So: **test cases** are approved in a second pass, after the plan body is
approved, because join-level cases cannot be written before the joins are known.
A **tester** then turns them into executable tests, once, against the frozen
contract. Phases write no tests. A test exists because a case demands it; a test
with no case is a finding, not a bonus, and the correspondence is checkable in
both directions.

## Consequences

- The test-writer seat stays; what changes is what it is given.
- The tester's output is neither reviewed nor approved. It is protected instead
  by ADR-0003: a join repairs a test's mechanics and never its intent, and the
  intent is the approved case.
- A phase's *Verification* field stops meaning "the cases this phase makes true"
  and starts meaning "the join that proves this phase" — which gives
  `plan-check` a new mechanical check: no phase without a join.
- Test counts stop being anyone's judgement. They follow the cases.
