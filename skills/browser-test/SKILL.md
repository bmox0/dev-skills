---
name: browser-test
description: Use when a change has to be seen working in the real thing — opening the app, clicking through a flow, filling a form, reading console errors or failed requests, recording WebSocket frames, or taking a screenshot. Drives a web app or an Electron build over CDP; replaces one-off Playwright scripts and browser MCP servers for every interactive check.
---

# Browser Test

Verification runs against one long-lived tab, driven by `tab.mjs`. The browser runs detached on its own profile with a CDP port; every command is a separate node process that connects, does one thing, and exits without closing the browser. The tab, its session, `localStorage` and any live connection survive between commands and between sessions.

## First, get `tab` on PATH

Every later call is then one short word. Run this once per machine:

```bash
node "$(printf '%s\n' "$HOME"/.claude/plugins/cache/dev-skills/dev-skills/*/skills/browser-test/tab.mjs | sort -V | tail -1)" shim
```

It writes `~/.local/bin/tab`, which re-resolves the plugin on each call and so survives version bumps. If it reports that the directory is not on PATH, keep using the full `node …/tab.mjs` path instead. `TAB_MJS` points the shim at a checkout, for anyone working on this skill itself. Everything below is written as `tab`.

## Then, point it at the app

```bash
tab up http://localhost:5173     # a web app — launches a browser if none is up
tab attach                       # an Electron build already serving CDP
tab help                         # full command list
tab down                         # when the task is finished
```

**Take the URL from the project's environment contract** — the `**Dev server.**` line in `CLAUDE.md` states the command and the url it serves on. Pass it to `up` once; the origin is remembered in `.ai-workflow/browser-test/state.json`, so later navigation is relative: `tab goto /settings`. The server has to be running already — this tool drives the app, it does not start it.

**Electron** is `attach`, not `up`. The app must have been started with `--remote-debugging-port=9222` (Electron reads it from `argv`, or `app.commandLine.appendSwitch("remote-debugging-port", "9222")`). `attach` adopts whatever is on that port and, from then on, this tool never launches a browser and never kills the app — `down` only detaches. Two things a renderer cannot show you: the **main process** is not a page target, so its `console` output is not in `logs` — read it from the terminal the app was started in; and a build with several windows exposes several page targets, so `tab pages` lists them and `tab use <n>` picks the one to drive.

## Core rule

**Never pull the page into context.** No `innerHTML` dumps, no accessibility trees, no "show me the DOM so I can find the button". Ask a precise question and get a precise answer back:

```bash
tab eval '[...document.querySelectorAll("[role=alert]")].map(e=>e.innerText)'
tab text '.row:first-child'
tab net --grep auth
```

That discipline is where the token saving comes from — the tool cannot enforce it. A whole login flow (click, fill, submit, assert the error, confirm the 401) costs under 400 tokens when driven this way.

## Which readout answers which question

**Did the app do the right thing?** `eval` — it returns exactly the expression's value.
**Did it break?** `logs --errors` — patched `console` plus `error`/`unhandledrejection`.
**Did the request go out, and what came back?** `net --grep <pattern>` — one line per `fetch`/XHR: `14:08:45 401 POST /auth/login (234ms)`.
**Does it look right?** `shot <name>`, then read the printed path — and only then. An image costs ~1.5k tokens, so it is for questions about layout, spacing and colour, never for finding out what the page contains.

`logs` and `net` read a 200-entry ring buffer kept in `sessionStorage`, so **they survive a reload** — a `goto` or `reload` still shows what happened before it. `--clear` before an action you want to read cleanly.

## Recording a socket

`ws [secs] [--reload]` records WebSocket frames through CDP, and it is the one command that reads traffic rather than driving the UI. **Run it only when the question is about the feed** — it is never part of a routine check.

It attaches to worker targets as well as the page, which is often the only way to see anything: a client that picks a worker implementation whenever `Worker` exists puts the socket somewhere nothing on the main thread can observe.

Reading the output: outgoing frames are plain text and readable as sent. Incoming frames are frequently `permessage-deflate` binary — by default only frame count and byte total mean anything, and `--inflate` decodes them:

```bash
tab ws 20 --reload --inflate --grep '"type":"position"'
```

That extension compresses a whole connection as one stream, so a frame only decodes when every frame before it was captured too — **`--inflate` needs `--reload`**, and the tool says so rather than guessing when it cannot decode. Pair it with `--grep` (a regex over the decoded text); without one it prints the first few frames. Snapshots are large, so grep for what you came for.

Cheaper first stop: if the app logs its own frames to the console, `logs --grep <pattern>` answers the question with no recording at all. Reach for `--inflate` when you need a frame the app does not log. Use `--reload` when you need the handshake — CDP cannot name a socket that was already open, though the tool caches `requestId → url` and labels it next time. Query strings are stripped everywhere, so session tokens never reach the output or the cache file.

## Rules that keep it working

**Leave it up for the length of a task, `down` when finished.** Relaunching per check throws away the logged-in session that makes the next check cheap.

**It never touches the human's own browser.** Own profile at `~/.cache/tab-browser-profile`, own port 9222; Chromium's single-instance lock is per profile, so their windows are untouched. Do not point `TAB_PROFILE` at their real profile. Brave, Chrome, Chromium and Edge are found in that order; `TAB_BROWSER` overrides.

**Artifacts go to `.ai-workflow/browser-test/`** — screenshots, the state file and the socket-url cache, under the same ignored directory the rest of a run uses.

**Nothing is injected into the app beyond the console/fetch/XHR hook.** `window.WebSocket` is deliberately left alone: frames are read through CDP, where patching cannot mislead and cannot break the app under test.

**Playwright is resolved, not installed.** The tool imports it from the project if it is a dependency, otherwise from the `npx` cache; if neither exists it says so. `npx playwright@latest --version` once is enough to populate the cache.
