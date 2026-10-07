---
name: browser-test
description: Use when a change has to be checked in the running app — clicking through a flow, filling a form, reading console errors or failed requests, recording WebSocket frames, or taking a screenshot. Runs the use cases as one Playwright scenario in a visible, long-lived tab the user can watch and sign in to; single commands dig into what failed. Drives a web app or an Electron build over CDP.
---

# Browser Test

The web e2e tool: `dev-skills:verify` drives a plan's use cases through it.

One long-lived tab, driven by `tab.mjs`. The browser runs detached on its own profile with a CDP port, in a window the user can watch; the tab, its session and `localStorage` survive between commands and between sessions. A check is a scenario: the whole Done as one Playwright file, run in that tab in one call. Single commands are for digging into what the scenario could not settle.

## First, get `tab` on PATH

Run this once per machine:

```bash
node "$(printf '%s\n' "$HOME"/.claude/plugins/cache/dev-skills/dev-skills/*/skills/browser-test/tab.mjs | sort -V | tail -1)" shim
```

It writes `~/.local/bin/tab`, which re-resolves the plugin on each call and so survives version bumps. If that directory is not on PATH, use the full `node …/tab.mjs` path instead. `TAB_MJS` points the shim at a checkout.

## A check is a scenario

1. **`tab up <url>`**, the url from the `**Dev server.**` line in the project's `AGENTS.md` or `CLAUDE.md`; the server must already run. Where the login is the user's, ask them to sign in in that window; the session stays in the profile.
2. **`tab map main`** — the controls a user can reach, one line each: `button "Export"`, `searchbox "Search orders"`, `link "ORD-1001" … "ORD-1025" (25 alike)`. Take selectors from it: `role=button[name='Export']`. Map again on each new screen.
3. **Write the whole Done as one file**, a step per use case, and edit it with the file editor:

```js
// done.mjs
export default async ({page, step, expect, net, errors, seen, shot, size}) => {
  await step("1. a wrong password shows an error", async () => {
    await page.fill("role=textbox[name='Email']", "demo@example.com")
    await page.click("role=button[name='Sign in']")
    await expect(() => page.locator("[role=alert]").innerText(), /wrong/i, "error text")
    return (await net()).join(", ")
  })
}
```

4. **`tab run done.mjs`** — one line per step, at 250 ms per action while the window is up, so the user can follow it; `--slow 0` when nobody watches.
5. **Dig into what is not `ok` by hand**, from where the run left the tab, then fix the step and `tab run done.mjs --only 3`.

`page` is the live tab with Playwright's API. `expect(fn, expected, label)` polls `fn` for 3 s and, when it fails, prints the states it saw; `net()` and `errors()` are this step's requests and console errors; `seen(locator)` is below; `size(w, h)` sets the width for the rest of the run; a step's return value is printed as its evidence.

Each step ends one of three ways. `ok`. `FAILED` — the app did something else, a click that something covers included; the run goes on. `NOT REACHED` — anything else threw, usually a locator that never appeared: the run stops, prints where, a screenshot, the last requests and errors, and leaves the tab there. A FAILED is a finding; a NOT REACHED is a question for the screenshot.

## What the user sees, not what the DOM says

**"Visible to the user" is a look.** Text in the DOM is not seen: white on white, transparent or covered text is there and invisible. `seen(locator)` answers `"visible"` or why not — covered by, transparent, text the colour of its background, outside the viewport; a screenshot taken at that moment is the other proof.

**Click as the user does.** Playwright's click refuses an element something covers, and the run reports that as FAILED. A click that only `el.click()` in `eval` gets through is a failed use case: the user cannot do it.

**The user may be watching.** They see what no check looks for — a form that works and looks wrong. Keep the window up while the scenario runs.

## Single commands

```bash
tab goto /settings     tab click <sel>     tab fill <sel> <value>     tab press <key>
tab text <sel>         tab eval <js>       tab seen <sel>             tab map [sel]
tab logs --errors      tab net --grep p    tab shot <name>            tab size 375x812
tab help               tab down
```

**Never pull the page into context.** No `innerHTML` dumps, no accessibility trees: `map` for the controls, a precise `eval` or `text` for a value. `logs` and `net` read a 200-entry buffer kept in `sessionStorage`, so they survive a reload; `--clear` before an action you want to read cleanly. `size` is emulated, so any width works, and it sticks until `size reset`. `shot` prints a path; read the image only for a question about looks — it costs ~1.5k tokens.

**Electron** is `tab attach`, not `up`: the app was started with `--remote-debugging-port=9222`, and from then on the tool never launches a browser and never kills the app — `down` only detaches. Its main process is not a page target, so its `console` is in the terminal that started it; several windows are several targets: `tab pages`, `tab use <n>`.

**A WebSocket feed** is `tab ws` — see [WEBSOCKETS.md](references/WEBSOCKETS.md); never part of a routine check.

## Rules that keep it working

**Leave it up for the length of a task, `down` when finished.** Relaunching throws away the session that makes the next check cheap.

**It never touches the human's own browser.** Own profile at `~/.cache/tab-browser-profile`, own port 9222. Do not point `TAB_PROFILE` at their real profile. Brave, Chrome, Chromium and Edge are found in that order; `TAB_BROWSER` overrides.

**Artifacts go to `.ai-workflow/browser-test/`** — screenshots and the state file, under `.ai-workflow/`, which git should ignore.

**Nothing is injected into the app beyond the console/fetch/XHR hook.** Frames are read through CDP, where patching cannot mislead and cannot break the app under test.

**Playwright is resolved, not installed** — from the project, else the `npx` cache; `npx playwright@latest --version` once populates it.
