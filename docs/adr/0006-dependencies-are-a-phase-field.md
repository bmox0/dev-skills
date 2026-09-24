---
status: proposed
---

# Dependencies are declared in the phase; the graph picture is rendered from it

The graph's edges live today as prose beneath the Topology table — "phase 10
additionally consumes 5, phase 11 consumes 6". The orchestrator therefore
re-derives them from prose on every run, by reading the whole plan, and that
reading is the context re-read every turn for the rest of the run. It is the
largest single line in the bill.

A phase declares `Depends on:` as a field of its own, grep-checkable like the
seven that already exist, and carrying only the **dependency** as ADR-0001
defines it. The ASCII graph the plan carries for the human is *rendered* from
those fields by a script rather than drawn by hand: two hand-kept records of one
thing diverge at the first edit.
