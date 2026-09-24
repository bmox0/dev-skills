---
status: proposed
---

# The join is the only barrier; phases are not scheduled by readiness

The obvious next step after widening the graph is to dispatch each phase the
moment its own dependencies land, instead of waiting for a whole row. Recomputed
against the swarm run's timestamps, it buys approximately nothing: every phase of
the row that looked blocked shared one slow ancestor, so nothing could in fact
have started earlier. The idle time at a barrier was real and the saving was not.

The **join** is therefore the only barrier, and it is *authored* rather than
computed — as many as the work needs, placed where the grilling put them, not one
every N phases. Everything between two joins dispatches at once, and that is safe
for the reason it was always safe: the **write-sets** are disjoint, which
`preflight --parallel` checks mechanically.
