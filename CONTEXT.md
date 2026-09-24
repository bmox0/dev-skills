# dev-skills — the graph execution model

The words the execution model uses: how an approved **plan** is cut into work
that runs as a dependency graph rather than as a chain.

[`references/VOCABULARY.md`](./references/VOCABULARY.md) is the glossary of the
pipeline **as shipped**, and the scripts anchor on its strings.

**The redesign has landed, and its vocabulary moved with it.** *Join*,
*Dependency*, *Phase Check*, *Test Case*, *Tester*, *Width* and *Attribution
Check* are defined in `references/VOCABULARY.md` and nowhere else. This file
keeps no copy of any of them: one owner per term, or the two drift and a reader
cannot tell which is current.

Two words are already **retired** there and stay retired: *checkpoint* (a review
dispatched between phases) and *segment* (a contiguous range of phases). Neither
may be revived — a run of phases is named by its range, as it is everywhere
else.
