---
status: proposed
---

# The join is a dispatched seat; the orchestrator never runs it

A **join** compiles the range before it, runs the tests, reads the red output and
repairs what did not meet. Done inside the orchestrator's conversation that is
precisely the disease ADR-0004 measured — the orchestrator at 86% of the bill,
two thirds of it re-reading its own context — and it would arrive several times
in a run rather than once, because there is more than one join.

So a join is dispatched like a phase. It differs in two ways only: it works on
the integration branch with a full tree rather than in a worktree, and it is the
most expensive seat in the run. The orchestrator receives its verdict, never its
output.

What is left in the orchestrator for one row: freeze the contract, dispatch the
row, run the attribution script, merge in phase order, dispatch the join. It
reads no code at any point, and its context grows with the number of phases
rather than with the size of the work.
