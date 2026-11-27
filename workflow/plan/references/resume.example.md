# Plan summary: Rebind keyboard shortcuts in Settings

[Full plan](example.md) · [Run configuration](../../run-file/references/example.run.toml)

Prototype choice: variant B from the Settings shortcuts plan.

## Result

In Settings → Shortcuts, you can change any action's key combination and reset
one or all bindings. Changes take effect immediately and survive a restart.
A combination already assigned to another action cannot be saved; the panel
names the action using it.

## Phases

`1 → 2 ∥ 3 · normal`

1. Store the user's overrides alongside settings; load and reset them without
   copying the default map.
2. Build the Shortcuts panel: action list, combination recording, conflict
   message and reset controls.
3. Apply binding changes while the app is running. This runs beside phase 2
   after both have the store from phase 1.

## Spec change

A taken combination cannot be saved. This prevents changing one action from
silently removing another action's shortcut.

## Checks

- Automated: tests, lint and type checks; branch review; e2e in the running app
  at 1280 and 1920 px. Cover changing a binding, rejecting a conflict,
  persistence after restart, resetting one or all bindings, and ignoring a
  lone modifier during recording.
- Manual: open Shortcuts and judge whether it reads like the rest of Settings
  — **you check**.

## Scope and limits

App shortcuts only. System-wide shortcuts, binding import/export and two-step
chords are outside this plan. Existing settings must remain intact.

## Your approval

After acceptance, open a merge request targeting `main`. Do you approve this
plan and run configuration as summarized here, or would you like a change?
Build starts when you ask separately.
