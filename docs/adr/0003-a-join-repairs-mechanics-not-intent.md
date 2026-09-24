---
status: proposed
---

# A join may repair a test's mechanics, never its intent

Tests reach a **join** having never been run. Some will be red because the code
is wrong and some because the test is. With only two outcomes available — adapt
the code, or stop the run as a `PLAN_CONFLICT` — the join does what a measured
run already did, and bends the code to the test.

There is therefore a third outcome. A join may change how a test does its work —
a spy's placement, a timeout, the order of a render — and may never change what
it asserts. What it asserts is the approved **test case**, and that belongs to
the plan. Every such repair is recorded as a divergence.

The same line settles duplication. Two identical implementations of one thing,
arriving from two phases of one row, are mechanics: the join collapses them and
records it. Two *different* approaches to one thing are intent, and that is a
`PLAN_CONFLICT`.
