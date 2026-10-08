# A plan: a worked example

Illustrative: the territories and commands are made up. It fits one screen.

```markdown
# Plan: Rebind keyboard shortcuts in Settings

Status: approved · branch `feat/shortcut-rebinding` · base `a1b2c3d`
Prototype: `.ai-workflow/prototypes/2026-09-26-settings-shortcuts.html`, variant B

## Result

In Settings → Shortcuts the user sees every action with its key combination,
records a new combination for any of them, is told when a combination is
taken, and can reset one or all to the defaults. A new binding works at once
and survives a restart.

## Approach

Bindings become user data. The defaults stay in code; the user's overrides are
stored with the other settings and laid over the defaults at start. The panel
edits overrides only.

- Overrides, not a copy of the whole map — new default shortcuts still reach a
  user who changed something else.
- A taken combination blocks saving and names the other action; no silent
  swap — chosen in the prototype review (variant B).
- Recording takes the next full combination; a lone modifier is ignored.

## Out of scope

- System-wide shortcuts.
- Import and export of bindings.
- Two-step chords.

## Phases

### 1. Overrides store — `done`

Keep the user's overrides with the other settings, lay them over the defaults at
start, and offer read, change and reset. True when a saved override is active
after a restart and a reset brings the default back.
Territory: `src/shared/shortcuts/`, `src/main/settings/`
Waits for: nothing

### 2. Shortcuts panel — `in progress`

The Settings tab from the prototype: the list, recording, the "taken" message,
reset one and reset all.
Territory: `src/renderer/settings/shortcuts/`
Waits for: 1 — `getBindings()`, `setOverride(action, keys)`, `reset(action?)`

### 3. Live rebinding — `in progress`

The app listens to the merged map, so a change applies without a restart.
Territory: `src/renderer/keyboard/`
Waits for: 1 — `getBindings()` and its change event. Runs beside 2.

## Checks

- Every phase: `pnpm test`, `pnpm lint`, `pnpm typecheck`, on its own territory
  while other phases run.
- After all phases: the same commands on the whole project; a review against
  the project's rules; e2e in the running Electron app through browser-test.
- Gate: wide — the bindings are stored user data that every window reads.

## Done

1. Settings → Shortcuts → "New task" → Record → ⌘⇧N → the row shows ⌘⇧N, and
   ⌘⇧N opens a new task.
2. Record ⌘K for "New task" while ⌘K opens search → "⌘K is taken by Search",
   and Save is disabled.
3. Restart the app → ⌘⇧N still opens a new task.
4. Reset on the row → the default comes back and works; Reset all → every row
   is back to its default.
5. Press ⌥ alone while recording → nothing is recorded.
6. Open Shortcuts → it reads like the rest of Settings — you check
```
