# The spec format

What must stay true about a product, and why, lives in `docs/spec/`, written by `spec.py` from plans. This file states the grammar and the commands.

## An area file

`docs/spec/<area>.md`. An area is a durable part of the product, not a folder and not a task.

```markdown
# Card editor

The form where a card's text and fields are edited.

### save-closes — Saving closes the editor
Why: the result shows in the list; the editor is a visit, not a place to stay.
- Change a card, press "Save" → the editor is closed, the list shows the new text.
```

A rule is what must stay true, whoever checks it: observable behaviour, an external constraint, or a look decided with a reason. Code structure goes to an ADR, words to `CONTEXT.md`, one-off checks nowhere. A rule has an ID, one statement, a one-line reason and at least one scenario; it may link to an ADR, as a Markdown link in `Why:`. A rule is addressed as `area#rule`; an ID is lowercase letters, digits and `-`.

## The plan's `## Spec` section

An entry is a first line — sign, ID, ` — `, the statement — and indented `Key: value` lines. An ID without `#` is the area itself.

```markdown
## Spec

+ card-editor — Card editor
  About: The form where a card's text and fields are edited.
+ user-events#period-default — The log opens on "All time"
  Why: an admin comes for the full history
  Done: 3
~ card-editor#save-closes — An explicit "Save" closes the editor, autosave does not
  Why: the result shows in the list; the editor is a visit, not a place to stay
  Done: 5, 6
- card-editor#keeps-draft
  Why: no draft is needed once the editor closes
```

When no rule changes, the section is the word `none`. A missing or empty section is an error.

- `+ area` adds an area; `About:` is its description, required.
- `+ area#rule` adds a rule; it needs `Why:` and `Done:`.
- `~` replaces the statement and the reason; its `Done:` items replace the scenarios, and without a `Done:` line the scenarios stay.
- `-` takes a rule out and needs `Why:`. An area that loses its last rule keeps its file.
- `Done:` lists item numbers of the plan's `## Done`. A scenario is the item's text without its `— you check` tail. A continuation line under a Done item joins it.
- The keywords `Why:`, `About:`, `Done:` are English; the content is in the plan's language.
- `+ area` entries apply first, then `~`, `-` and `+ rule` in order.

## Commands

```bash
python3 "<this skill's directory>/spec.py" check [--base REV] PLAN
python3 "<this skill's directory>/spec.py" write [--base REV] PLAN
python3 "<this skill's directory>/spec.py" list
python3 "<this skill's directory>/spec.py" show ID
```

`<this skill's directory>` is the folder `SKILL.md` sits in. The script works in the current git repository; a worktree has its own spec.

| Command | Does |
|---|---|
| `check` | checks the section against `docs/spec/` at the base; writes nothing |
| `write` | runs `check`, makes `docs/spec/` equal to the base plus the section, writes the archive record; `none` writes nothing, or restores the base after this plan's earlier write |
| `list` | the working tree's areas, `<area> — <title>`, each followed by its rules indented, `  <area>#<rule> — <statement>`; an empty spec prints nothing |
| `show ID` | the rule block (`<id> — <statement>`, `Why:`, the `- ` scenarios), then each archive record whose `Spec` section names it, newest first by file name, under a header `## archive/<file> — <title>` with that rule's entry lines as written |

**The base.** `--base REV`, else the base in the plan's `Status:` line, else `HEAD`. A second `write` for the same plan replaces the first, whatever changed in the plan since, except its `# ` title: that names the plan, so a retitled plan's `write` refuses, and a `write` after the base moved lands on the fresh spec. The earlier write is checked against its archive record alone: `docs/spec/` must equal the base plus the record's `Done` and `Spec`. `write` refuses, naming paths, when it does not (a hand edit on top, another plan's write, a moved base).

**Exit codes.** 0 success. 1: problems, one per line as `<plan>:<line>: <message>`, all in one run sorted by line; also outside a git repository, an unknown base, or `show` of a non-rule (`spec.py: no rule <id>` on stderr). 2: a bad argument, `show` without an ID included.

**What `check` reports.** No `## Spec` section. A line that is not an entry or a `Why:`/`About:`/`Done:` line. A sign with an ID of the wrong kind. A missing statement; a missing or empty `Why:`; a new area without `About:`. An area or rule that exists when added, or does not exist when changed or removed, or whose area is neither there nor added. An added rule without `Done:`. A `Done:` item the plan does not have. An empty or a second `## Spec` section (`## ` inside a code fence is not a heading). An archive record of the plan's file name at the base. A plan file without a `# ` title line. In a base area file (`docs/spec/<area>.md:<line>`), what `write` would drop or alter: a stray line under a rule, a second `Why:`, a rule without `Why:` or with an empty one, no title.

**What `write` touches.** The area files, rendered in one normalised format; files of areas no longer in the spec are deleted. `docs/spec/README.md` is created with the folder; `README.md` and `archive/` are never rewritten otherwise, and `list` and `show` skip them.

**The archive record.** `docs/spec/archive/<the plan's file name>`: the line `This is history; the rules that hold now are in `docs/spec/`.`, a blank line, then the plan's title, Result, Approach, Out of scope, `Done` and `Spec`, copied as they are; a section the file lacks is skipped. A record without `Done` (older ones) stays valid: `show` lists it, and nothing complains about it at the base.
