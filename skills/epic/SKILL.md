---
name: epic
description: Keep work that needs more than one plan — the shared decisions and the ordered list of plans. Only when the user asks for an epic.
---

# Epic

An epic exists only on the user's word; by default the work is one plan. It
holds what the plans share and the order they go in.

Write it to `.ai-workflow/epics/<topic>.md`:

```markdown
# Epic: <topic>

## Goal
<what the whole body of work makes possible, in the user's terms>

## Decisions
- <decision> — <the reason>

## Out of scope
- <what a reader would assume is included and is not>

## Interfaces
<shapes passed between plans, written once>

## Plans
| # | Plan | Territory | Waits for | Status |
|---|---|---|---|---|
| 1 | Transport and tool registration | `server/transport/` | — | merged |
| 2 | First tool over the service layer | `server/tools/` | 1 | building |
| 3 | Call log and access revocation | `server/log/`, `server/auth/` | 1 | |
```

The decisions bind every plan, and no plan reopens one. A decision that turns
up while planning one plan and binds another moves here; it is never copied.

Each row is a finished feature, not a step. Its territory is where its plan
will write; rows whose territories overlap wait for each other. Its plan is written when it is next
(`dev-skills:plan`), with `Epic:` pointing here, and starts from the default
branch once the plans it waits for have merged. A row's Status is empty until
its plan exists. Rows merge or split as planning shows what fits: the list is
corrected, not defended.

End with the list in front of the user; the first row that waits for nothing is
next.
