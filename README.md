# dev-skills

Claude Code starts writing the moment you describe a task. Most of the time that
is exactly what you want. The rest of the time what comes back is fluent,
confident, and built on an understanding of the problem you never agreed to —
and you find that out after reading the diff.

dev-skills puts a sequence between the idea and the commit. You say what you
want; it asks questions until you both mean the same thing. That agreement
becomes a plan you approve before anything is built, and a set of test cases you
approve alongside it — whatever is not in them is not checked. Then it builds,
and two gates that did not write any of it judge the result: one on the code, one
on the running system. What lands is one commit, on its own branch, that you read
before it goes anywhere.

## A run, end to end

1. **[`dev-skills:grill`](skills/grill/SKILL.md)** — questions, until the thing
   you asked for and the thing that was heard are the same thing. No document,
   no code: it ends in agreement, and then a stop.
2. **[`dev-skills:plan`](skills/plan/SKILL.md)** — that agreement written down
   as a contract precise enough for someone who never saw the conversation. You
   approve it, or you send it back; then the test cases are grilled out of you
   in the same sitting, and you approve those too.
3. **[`dev-skills:implement`](skills/implement/SKILL.md)** — a branch or a
   worktree first, then the tests, then the phases. At the end two gates on
   clean contexts: one reads the whole range against the plan, one drives the
   approved cases on a live system. Neither fixes anything; they report, and
   only a blocker buys a fix round.
4. **[`dev-skills:finish`](skills/finish/SKILL.md)** — the run collapses into a
   single commit, you read exactly that commit, and it integrates.

The ceremony sits where it costs money and rewrites history. The last two —
`dev-skills:implement` and `dev-skills:finish` — are marked
`disable-model-invocation` and are simply absent from Claude's tool list, so it
can name them but never call them. A run's *execution* begins because you typed
it, never because something decided your task looked big enough to warrant one.

The first two Claude can reach for, and should: asking to talk a fuzzy task
through, or to turn an agreed understanding into a plan, is not a decision worth
a gate. Nothing is spent and nothing is rewritten until you type the third.

### Other ways in

Not every task is a feature. [`dev-skills:bug`](skills/bug/SKILL.md) reproduces
a symptom and pins it with a failing test before anyone is allowed to propose a
fix — the one to reach for fastest, because the mistake it prevents is made in
the first reply.
[`dev-skills:scout`](skills/scout/SKILL.md) explains unfamiliar code without
touching it. [`dev-skills:refactor`](skills/refactor/SKILL.md) changes the shape
of code under a contract that its behaviour does not.
[`dev-skills:tests`](skills/tests/SKILL.md) is for when the tests are the
deliverable.

## What it enforces

Discipline a model has to remember is not discipline. Three git hooks run on
every relevant tool call, whether or not a run is open:

- **Commits.** Blanket staging is refused — `git add .`, `-A` and
  `git commit -a` all sweep up work nobody looked at, including a file another
  agent is halfway through. Subjects that are not Conventional Commits are
  refused too, as are Claude attribution trailers.
- **History, while a run is open.** `reset --hard`, `rebase`, `merge` and
  `--amend` belong to [`dev-skills:finish`](skills/finish/SKILL.md), which
  records a numbered recovery ref before it touches anything. Outside a run the
  hook is silent, so ordinary work in ordinary repositories is unaffected.
- **The default branch.** In a repository carrying a `.branch-guard` file,
  edits and commits on `main` are blocked until the work is on a branch of its
  own.

All three fail open: whatever they cannot parse confidently, they allow. A
guard that blocks the wrong thing is worse than one that misses.

One more hook does the opposite of guarding: the moment a prototype is written
to `.ai-workflow/plans/<plan>/prototypes/`, it opens in the browser — `open` on
macOS, `xdg-open` elsewhere, `DEV_SKILLS_OPEN_CMD` to pick your own. You never
ask for it to be opened.

## Install

```
/plugin marketplace add bmox0/dev-skills
/plugin install dev-skills@dev-skills
```

Then restart the session. The repository carries its own
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json), so it is a
marketplace holding exactly one plugin — itself. Claude Code clones it, keeps it
current, and `/plugin uninstall dev-skills` takes it back out again.

Installing also brings four subagents — `test-writer`, `implementer`, `gate-a`
and `gate-b` — which [`dev-skills:implement`](skills/implement/SKILL.md)
dispatches and you never call directly, and the hooks above
([`hooks/hooks.json`](hooks/hooks.json)).

## Every skill

The pipeline is four of these. The rest are things you invoke on their own, or
that the pipeline reads as it works. Each one documents its own use inside its
`SKILL.md`.

| Skill | What it's for |
|---|---|
| [`dev-skills:bootstrap`](skills/bootstrap/SKILL.md) | injected at session start; states the one rule and lists what exists |
| [`dev-skills:browser-test`](skills/browser-test/SKILL.md) | drive a web app or an Electron build over CDP, one long-lived tab, precise readouts |
| [`dev-skills:bug`](skills/bug/SKILL.md) | reproduce a bug, find its root cause, leave behind a failing test that pins it |
| [`dev-skills:commit-work`](skills/commit-work/SKILL.md) | review and stage changes, split them into logical commits, write clear messages |
| [`dev-skills:domain-modeling`](skills/domain-modeling/SKILL.md) | build and sharpen a project's glossary, and record an ADR when one is earned |
| [`dev-skills:epic`](skills/epic/SKILL.md) | write the epic that holds a body of work too large for one plan |
| [`dev-skills:finish`](skills/finish/SKILL.md) | close out a run into one commit and hand it to the human |
| [`dev-skills:grill`](skills/grill/SKILL.md) | interview an idea into a shared understanding before anything is planned |
| [`dev-skills:grill-with-docs`](skills/grill-with-docs/SKILL.md) | grilling that also captures glossary terms and ADRs as they settle |
| [`dev-skills:guardrails`](skills/guardrails/SKILL.md) | set up Claude Code hooks that block dangerous git commands |
| [`dev-skills:handoff`](skills/handoff/SKILL.md) | pack this session into a document a fresh agent continues from |
| [`dev-skills:implement`](skills/implement/SKILL.md) | execute an approved plan, from workspace through both gates |
| [`dev-skills:improve`](skills/improve/SKILL.md) | scan a codebase for deepening opportunities, then work through one |
| [`dev-skills:merge-conflicts`](skills/merge-conflicts/SKILL.md) | resolve an in-progress git merge or rebase conflict |
| [`dev-skills:plan`](skills/plan/SKILL.md) | write the implementation plan a cold, cheap implementer can build from |
| [`dev-skills:pre-commit`](skills/pre-commit/SKILL.md) | set up Husky pre-commit hooks with lint-staged and type checking |
| [`dev-skills:prototype`](skills/prototype/SKILL.md) | build a throwaway prototype to answer a design question |
| [`dev-skills:refactor`](skills/refactor/SKILL.md) | restructure, migrate, or upgrade code without changing its behaviour |
| [`dev-skills:research`](skills/research/SKILL.md) | investigate a question against primary sources and capture the findings |
| [`dev-skills:review`](skills/review/SKILL.md) | review code against the same criteria the pipeline's own gates use |
| [`dev-skills:review-criteria`](skills/review-criteria/SKILL.md) | the shared standard for what counts as a review finding |
| [`dev-skills:scout`](skills/scout/SKILL.md) | map unfamiliar code and answer a specific question about it, read-only |
| [`dev-skills:tdd`](skills/tdd/SKILL.md) | the red-green-refactor discipline the implementer builds by |
| [`dev-skills:tests`](skills/tests/SKILL.md) | cover untested code, or repair tests that lie |
| [`dev-skills:writing-great-skills`](skills/writing-great-skills/SKILL.md) | design, audit, or edit a skill so it behaves predictably |

One file is not a skill and is worth knowing about:
[`references/VOCABULARY.md`](references/VOCABULARY.md) defines every term the
pipeline uses — phase, brief, dispatch, frozen contract, write-set, fact,
decision — plus the literal strings the plan-parsing scripts anchor on. When two
documents here use the same word, that is where they agree on what it means.

## Checking this repository

Two commands, answering different questions. Neither needs anything installed:
bash and the Python standard library.

`scripts/check` asks whether the tree is sound — every cross-reference resolves,
no skill name has drifted, the plugin manifest and every `SKILL.md` frontmatter
parse. That last one matters more than it sounds: frontmatter Claude Code cannot
parse drops every field silently at load, and nothing else catches it.

`scripts/test` runs the behavioural suite over the scripts a run leans on —
brief extraction, the run marker's lifecycle, the mechanical path check, the
squash and its recovery refs.

Those tests cover code that already worked, so a new one passes the moment it is
written and proves nothing by passing. Each therefore carries a recorded
mutation instead. `scripts/test --mutations` breaks the production file in the
exact way the test claims to catch, watches that named test fail, puts the file
back, and checks the tree is clean again. A patch that no longer applies is
reported `stale` rather than skipped — that is the signal that a rewrite changed
the thing a test was pinning, and it is meant to be loud.

## Licence

MIT — see [LICENSE](LICENSE).
