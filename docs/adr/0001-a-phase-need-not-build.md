---
status: proposed
---

# A phase need not build; the join is where the code first has to work

Execution came out near-linear because every worker had to finish green. A phase
importing a module a sibling was still writing could not typecheck, so it waited
— which made the *build* the graph's edges. A measured 13-phase plan produced a
graph six waves deep whose wide rows were all leaves, while the plan's own frozen
contracts already permitted a depth of three.

We delete the requirement rather than work around it. The **Frozen Contract**
becomes complete by construction — it is what you can write a *compiling import*
against, module paths and exported names included, not only types — so a phase
writes code against modules that do not exist yet and compiles nothing, tests
nothing and lints nothing. Its only **dependency** is needing another phase's
file in order to edit it. Everything else runs at once, and the **join** is where
the code first has to work.

## Considered options

- **Generate stubs from the frozen contract** so each worker's build stays green.
  Rejected: machinery built to preserve a requirement we can simply remove.
- **Keep the per-phase green build.** Rejected on measurement — it is what held
  the graph at six waves against contracts that permitted three.

## Consequences

- A phase becomes the cheapest and most parallel seat in the run; the **join**
  becomes the most expensive one, and the planner sizes it deliberately.
- The cost of a wrong contract is multiplied by the width of the row built
  against it. The contract is now the thing to grill hardest at plan approval.
- A phase runs exactly one command, the **Phase Check** its environment contract
  names, and no more. "Run whatever you can" was rejected: a conditional rule
  fails precisely where the actor is busy.
- A phase is still not blind — it reads the repository. What it cannot see is a
  sibling in the same row. So anything two phases of one row would both need has
  exactly one owner, named in the plan or landed earlier; and an entity that is
  in neither the contract nor the tree is a **Decision**, which the implementer
  escalates instead of inventing.
- Conversely, a module **named in the contract and absent from the tree** is the
  expected state, not a problem to solve. The implementer writes the import and
  moves on: it does not go looking for the module, and above all it does not
  create it. At width, that is how two phases come to own one file.
- Nothing at all is verified between plan approval and the first **join**. That
  is bounded the way a fix round is: a join that does not go green in two
  attempts is a plan defect and goes to the human.
- The plan must now carry the conventions themselves — style, architecture, what
  not to introduce — and not merely the commands that would have checked them,
  because no phase runs those commands any more.
