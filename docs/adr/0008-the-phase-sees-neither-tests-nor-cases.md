---
status: proposed
---

# A phase sees neither the executable tests nor the test cases

The failure this prevents was reported from experience rather than measured here:
tests are generated, the implementation covers the 80% the test names and gets
the remaining 20% wrong, and the tests are then rewritten to match. The code was
written to the test instead of to the plan.

Forbidding that by rule is weak, and the swarm's own doctrine says why — write
isolation is physical, not agreed. So the **tester** commits to a branch of its
own, worker worktrees are cut from a tip that does not contain it, and the
**join** merges it before it runs anything. A phase cannot read a test because
the test is not there.

The same reasoning takes the cases with it. A phase's *Verification* now names
the **join** that proves it rather than a list of `TC-` ids, so a phase's entire
specification is *Becomes true*, *How* and the **Frozen Contract**. That is
exactly what the plan's own sufficiency test already demands of those fields —
two competent engineers reading the phase write functionally identical code — and
a **test case** is about the surface a join assembles, which is not the phase's
business.

## Consequences

- A thin phase can no longer be rescued by an implementer reading the test to
  work out what was meant. That is the point: it surfaces as a bad phase at plan
  approval, instead of as production code shaped by a spy's placement.
- A join merges one branch more than it otherwise would.
