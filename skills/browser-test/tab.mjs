#!/usr/bin/env node
import {spawn, execFileSync} from "node:child_process"
import {chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from "node:fs"
import {homedir} from "node:os"
import path from "node:path"
import {fileURLToPath, pathToFileURL} from "node:url"
import zlib from "node:zlib"

const HERE = fileURLToPath(import.meta.url)

const OUT = process.env.TAB_OUT ?? path.resolve(process.cwd(), ".ai-workflow", "browser-test")
const SHOTS = path.join(OUT, "shots")
const STATE_FILE = path.join(OUT, "state.json")

const PROFILE = process.env.TAB_PROFILE ?? path.join(homedir(), ".cache", "tab-browser-profile")
const HEADLESS = process.env.TAB_HEADLESS === "1"
const TIMEOUT = Number(process.env.TAB_TIMEOUT ?? 8000)
const MAX_OUT = Number(process.env.TAB_MAX_OUT ?? 4000)

const BROWSERS = [
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/usr/bin/brave-browser",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
  "/usr/bin/microsoft-edge",
]

function readState() {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"))
  } catch {
    return {}
  }
}

function writeState(patch) {
  const next = {...state, ...patch}
  try {
    mkdirSync(OUT, {recursive: true})
    writeFileSync(STATE_FILE, JSON.stringify(next))
  } catch {}
  Object.assign(state, next)
}

const state = readState()
const PORT = Number(process.env.TAB_PORT ?? state.port ?? 9222)
const BASE = process.env.TAB_BASE ?? state.base ?? "http://localhost:5173"
const ATTACHED = state.mode === "attach"

const HOOK = `(() => {
  if (window.__tab) return "already"
  const KEY = "__tab_buf", CAP = 200
  let buf = []
  try { buf = JSON.parse(sessionStorage.getItem(KEY)) || [] } catch {}
  let pending = false
  const flush = () => { pending = false; try { sessionStorage.setItem(KEY, JSON.stringify(buf)) } catch {} }
  const push = e => {
    buf.push(e)
    if (buf.length > CAP) buf.splice(0, buf.length - CAP)
    if (!pending) { pending = true; queueMicrotask(flush) }
  }
  window.__tab = {buf, push, clear() { buf.length = 0; flush() }}
  const t = () => new Date().toISOString().slice(11, 23)
  const str = v => { try { return typeof v === "string" ? v : JSON.stringify(v) } catch { return String(v) } }
  for (const lvl of ["log", "info", "warn", "error", "debug"]) {
    const orig = console[lvl].bind(console)
    console[lvl] = (...a) => { push({k: "log", lvl, t: t(), m: a.map(str).join(" ").slice(0, 600)}); orig(...a) }
  }
  addEventListener("error", e => push({k: "log", lvl: "error", t: t(), m: "uncaught: " + (e.message || "") + " @" + (e.filename || "").split("/").pop() + ":" + (e.lineno || 0)}))
  addEventListener("unhandledrejection", e => push({k: "log", lvl: "error", t: t(), m: "unhandled: " + str(e.reason && (e.reason.message || e.reason)).slice(0, 400)}))
  const of = window.fetch
  window.fetch = async (...a) => {
    const url = (a[0] && a[0].url) || String(a[0])
    const m = String((a[1] && a[1].method) || (a[0] && a[0].method) || "GET").toUpperCase()
    const s = Date.now()
    try {
      const r = await of(...a)
      push({k: "net", t: t(), m, url: String(url).slice(0, 300), st: r.status, ms: Date.now() - s})
      return r
    } catch (err) {
      push({k: "net", t: t(), m, url: String(url).slice(0, 300), st: "ERR", err: String(err && err.message).slice(0, 200), ms: Date.now() - s})
      throw err
    }
  }
  const OX = XMLHttpRequest.prototype.open, SX = XMLHttpRequest.prototype.send
  XMLHttpRequest.prototype.open = function (m, u, ...r) { this.__tm = m; this.__tu = u; return OX.call(this, m, u, ...r) }
  XMLHttpRequest.prototype.send = function (...r) {
    const s = Date.now()
    this.addEventListener("loadend", () => push({k: "net", t: t(), m: this.__tm, url: String(this.__tu).slice(0, 300), st: this.status, ms: Date.now() - s}))
    return SX.apply(this, r)
  }
  return "installed"
})()`

function out(s) {
  const text = String(s)
  process.stdout.write(text.length > MAX_OUT ? text.slice(0, MAX_OUT) + `\n… (+${text.length - MAX_OUT} chars truncated)\n` : text.endsWith("\n") ? text : text + "\n")
}

function die(msg) {
  process.stderr.write("ERR: " + String(msg).split("\n")[0] + "\n")
  process.exit(1)
}

const sleep = ms => new Promise(r => setTimeout(r, ms))

async function loadChromium() {
  try {
    return (await import("playwright")).chromium
  } catch {}
  const npx = path.join(homedir(), ".npm", "_npx")
  if (existsSync(npx)) {
    for (const d of readdirSync(npx)) {
      const p = path.join(npx, d, "node_modules", "playwright", "index.mjs")
      if (existsSync(p)) return (await import(pathToFileURL(p).href)).chromium
    }
  }
  die("playwright not found — run `npx playwright@latest --version` once, or npm i -D playwright")
}

async function cdp(fn) {
  const info = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()
  const sock = new WebSocket(info.webSocketDebuggerUrl)
  const pending = new Map()
  const handlers = []
  let seq = 0
  sock.addEventListener("message", ev => {
    const msg = JSON.parse(ev.data)
    if (msg.id && pending.has(msg.id)) {
      const {resolve, reject} = pending.get(msg.id)
      pending.delete(msg.id)
      if (msg.error) reject(new Error(msg.error.message))
      else resolve(msg.result)
    } else if (msg.method) {
      for (const h of handlers) h(msg)
    }
  })
  await new Promise((res, rej) => {
    sock.addEventListener("open", res, {once: true})
    sock.addEventListener("error", () => rej(new Error("cannot open the CDP socket")), {once: true})
  })
  const send = (method, params = {}, sessionId) =>
    new Promise((resolve, reject) => {
      const id = ++seq
      pending.set(id, {resolve, reject})
      sock.send(JSON.stringify(sessionId ? {id, method, params, sessionId} : {id, method, params}))
    })
  try {
    return await fn({send, on: h => handlers.push(h)})
  } finally {
    sock.close()
  }
}

function b64len(s) {
  if (!s) return 0
  const pad = s.endsWith("==") ? 2 : s.endsWith("=") ? 1 : 0
  return Math.max(0, Math.floor((s.length * 3) / 4) - pad)
}

const kb = n => (n < 1024 ? n + "B" : (n / 1024).toFixed(1) + "KB")

const isRealPage = u => Boolean(u) && !/^(about:|chrome:|brave:|edge:|devtools:)/.test(u)

function cleanUrl(u) {
  try {
    const x = new URL(u)
    return x.origin + x.pathname + (x.search ? "?…" : "")
  } catch {
    return String(u).split("?")[0]
  }
}

const SYNC = Buffer.from([0x00, 0x00, 0xff, 0xff])

/**
 * Inflates a connection's incoming binary frames, in arrival order, through one raw-deflate stream.
 *
 * `permessage-deflate` compresses the whole connection as a single stream, so a frame is only
 * decodable when every frame before it has been fed in too — hence `--reload`, which reopens the
 * socket and puts the recording at the start of the stream. Capturing mid-stream throws, and that
 * is reported rather than guessed around.
 */
async function inflateFrames(b64s) {
  const inflater = zlib.createInflateRaw()
  let failure = null
  inflater.on("error", err => (failure ??= err.message))
  const texts = []

  for (const b64 of b64s) {
    if (failure) break
    const chunks = []
    const onData = chunk => chunks.push(chunk)
    inflater.on("data", onData)
    inflater.write(Buffer.concat([Buffer.from(b64, "base64"), SYNC]))
    await new Promise(resolve => inflater.flush(zlib.constants.Z_SYNC_FLUSH, resolve))
    inflater.removeListener("data", onData)
    texts.push(Buffer.concat(chunks).toString("utf8"))
  }

  return {texts, failure}
}

/** The `← ` lines for a connection's inflated incoming frames, filtered and truncated for reading. */
async function inflatedLines(c, {frames, grep, reload}) {
  const {texts, failure} = await inflateFrames(c.blobs)
  if (failure) {
    const hint = reload ? "" : " — pass --reload so recording starts at the beginning of the stream"
    return [`  inflate failed after ${texts.length}/${c.blobs.length} frames: ${failure}${hint}`]
  }

  const rx = grep ? new RegExp(grep, "i") : null
  const matched = texts.map((t, i) => ({t, i})).filter(({t}) => t !== "7" && (!rx || rx.test(t)))
  const limit = rx ? 20 : Math.max(frames, 3)
  const width = rx ? 900 : 240
  const head = `  inflated ${texts.length} frames${rx ? `, ${matched.length} matching /${grep}/` : ""}:`

  return [
    head,
    ...matched.slice(0, limit).map(({t}) => "    ← " + (t.length > width ? t.slice(0, width) + " …" : t)),
    ...(matched.length > limit ? [`    … +${matched.length - limit} more`] : []),
  ]
}

async function recordWs(seconds, {reload, frames, inflate, grep}) {
  const urlFile = path.join(OUT, "ws-urls.json")
  let known = {}
  try {
    known = JSON.parse(readFileSync(urlFile, "utf8"))
  } catch {}
  return cdp(async ({send, on}) => {
    const conns = new Map()
    const where = new Map()
    const touch = (rid, sid) => {
      let c = conns.get(rid)
      if (!c) {
        c = {url: known[rid] ?? "(opened before recording)", sent: [], recvN: 0, recvBytes: 0, texts: [], blobs: [], src: where.get(sid) ?? "page"}
        conns.set(rid, c)
      }
      return c
    }
    on(async msg => {
      const {method, params, sessionId} = msg
      if (method === "Target.attachedToTarget") {
        const sid = params.sessionId
        where.set(sid, params.targetInfo.type)
        send("Network.enable", {}, sid).catch(() => {})
        send("Target.setAutoAttach", {autoAttach: true, waitForDebuggerOnStart: true, flatten: true}, sid).catch(() => {})
        send("Runtime.runIfWaitingForDebugger", {}, sid).catch(() => {})
        return
      }
      if (!method || !method.startsWith("Network.webSocket")) return
      const c = touch(params.requestId, sessionId)
      const f = params.response
      if (method === "Network.webSocketCreated") {
        c.url = cleanUrl(params.url)
        known[params.requestId] = c.url
      }
      else if (method === "Network.webSocketFrameSent") c.sent.push(String(f.payloadData ?? "").slice(0, 240))
      else if (method === "Network.webSocketFrameReceived") {
        c.recvN++
        if (f.opcode === 1) {
          c.recvBytes += String(f.payloadData ?? "").length
          if (c.texts.length < frames) c.texts.push(String(f.payloadData ?? "").slice(0, 240))
        } else {
          c.recvBytes += b64len(f.payloadData)
          c.binary = true
          if (inflate) c.blobs.push(String(f.payloadData ?? ""))
        }
      } else if (method === "Network.webSocketClosed") c.closed = true
      else if (method === "Network.webSocketFrameError") c.error = params.errorMessage
    })
    const {targetInfos} = await send("Target.getTargets")
    const pages = targetInfos.filter(t => t.type === "page")
    const target = pages.find(t => isRealPage(t.url)) ?? pages[0]
    if (!target) die("no page target")
    const {sessionId} = await send("Target.attachToTarget", {targetId: target.targetId, flatten: true})
    where.set(sessionId, "page")
    await send("Network.enable", {}, sessionId)
    await send("Target.setAutoAttach", {autoAttach: true, waitForDebuggerOnStart: true, flatten: true}, sessionId)
    if (reload) {
      await sleep(200)
      await send("Page.reload", {}, sessionId).catch(() => {})
    }
    await sleep(seconds * 1000)
    try {
      mkdirSync(OUT, {recursive: true})
      writeFileSync(urlFile, JSON.stringify(known))
    } catch {}
    if (!conns.size) return `(no websocket traffic in ${seconds}s)`
    const blocks = []
    for (const c of conns.values()) {
      const head = `${c.src === "worker" ? "worker" : c.src} · ${c.url}${c.closed ? " · CLOSED" : ""}${c.error ? " · " + c.error : ""}`
      const shown = c.sent.slice(0, Math.max(frames, 20))
      const sent = c.sent.length
        ? [`  sent ${c.sent.length}:`, ...shown.map(s => "    → " + s), ...(c.sent.length > shown.length ? [`    … +${c.sent.length - shown.length} more`] : [])]
        : ["  sent 0"]
      const got = [`  recv ${c.recvN} frames, ${kb(c.recvBytes)}${c.binary ? " (binary)" : ""}`, ...c.texts.map(s => "    ← " + s)]
      if (inflate && c.blobs.length) got.push(...(await inflatedLines(c, {frames, grep, reload})))
      blocks.push([head, ...sent, ...got].join("\n"))
    }
    return blocks.join("\n\n")
  })
}

async function cdpAlive() {
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/json/version`, {signal: AbortSignal.timeout(700)})
    return r.ok
  } catch {
    return false
  }
}

/**
 * Guarantees a CDP endpoint on PORT, and reports whether this call is what started it.
 *
 * In `attach` mode the endpoint belongs to an application this tool did not start — an Electron
 * build, a browser the human launched — so a dead port is a failure to report, never a licence to
 * launch one.
 */
async function ensureBrowser() {
  if (await cdpAlive()) return false
  if (ATTACHED) die(`nothing is listening on CDP port ${PORT} — start the app with --remote-debugging-port=${PORT}, or run \`up\` to go back to a launched browser`)
  const browser = process.env.TAB_BROWSER ?? BROWSERS.find(existsSync)
  if (!browser) die("no Chromium-family browser found — set TAB_BROWSER to one")
  if (!existsSync(browser)) die(`browser not found at ${browser}`)
  mkdirSync(PROFILE, {recursive: true})
  const args = [
    `--user-data-dir=${PROFILE}`,
    `--remote-debugging-port=${PORT}`,
    "--remote-allow-origins=*",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-features=Translate,BraveRewards,BraveWallet",
    "--window-size=1440,900",
    "about:blank",
  ]
  if (HEADLESS) args.unshift("--headless=new")
  spawn(browser, args, {detached: true, stdio: "ignore"}).unref()
  for (let i = 0; i < 80; i++) {
    if (await cdpAlive()) return true
    await sleep(250)
  }
  die("browser started but never opened the CDP port")
}

function realPages(ctx) {
  return ctx.pages().filter(p => !p.url().startsWith("devtools://"))
}

async function getPage(browser) {
  const ctx = browser.contexts()[0]
  if (!ctx) die("no browser context")
  const pages = realPages(ctx)
  const chosen = Number.isInteger(state.page) ? pages[state.page] : null
  const page = chosen ?? pages.find(p => isRealPage(p.url())) ?? pages[0] ?? (await ctx.newPage())
  page.setDefaultTimeout(TIMEOUT)
  return {ctx, page}
}

async function install(page) {
  try {
    await page.evaluate(HOOK)
  } catch {}
}

function abs(url) {
  if (!url) return BASE
  if (/^[a-z]+:\/\//i.test(url)) return url
  return BASE.replace(/\/$/, "") + (url.startsWith("/") ? url : "/" + url)
}

/** Remembers an absolute navigation target's origin, so later relative paths resolve against it. */
function rememberBase(url) {
  if (!/^https?:\/\//i.test(url)) return
  try {
    writeState({base: new URL(url).origin})
  } catch {}
}

function flag(argv, name, fallback) {
  const i = argv.indexOf("--" + name) === -1 ? argv.indexOf("-" + name) : argv.indexOf("--" + name)
  if (i === -1) return fallback
  const v = argv[i + 1]
  argv.splice(i, v && !v.startsWith("--") ? 2 : 1)
  return v && !v.startsWith("--") ? v : true
}

function fmt(entries) {
  return entries
    .map(e =>
      e.k === "net"
        ? `${e.t} ${String(e.st).padEnd(3)} ${e.m.padEnd(4)} ${e.url}${e.err ? " — " + e.err : ""} (${e.ms}ms)`
        : e.k === "ws"
          ? `${e.t} ws   ${e.ev} ${e.url}`
          : `${e.t} ${e.lvl.padEnd(5)} ${e.m}`,
    )
    .join("\n")
}

class Failed extends Error {}

const TRACKED = new Set(["document", "fetch", "xhr"])

/** The first line of a Playwright error, plus the locator it was waiting for when the call log names one. */
function reason(err) {
  const lines = String(err?.message ?? err).replace(/\x1b\[[0-9;]*m/g, "").split("\n")
  const waiting = lines.find(l => l.includes("waiting for"))
  return lines[0] + (waiting ? " — " + waiting.trim().replace(/^-\s*/, "") : "")
}

/** What a user would see of an element: "visible", or the reason they would not. */
function seenBy(el) {
  const r = el.getBoundingClientRect()
  if (!r.width || !r.height) return "zero size"
  if (r.bottom <= 0 || r.right <= 0 || r.top >= innerHeight || r.left >= innerWidth) return "outside the viewport"
  for (let e = el; e; e = e.parentElement) {
    const s = getComputedStyle(e)
    if (s.display === "none" || s.visibility === "hidden") return "hidden"
    if (Number(s.opacity) < 0.1) return `transparent (opacity ${s.opacity})`
  }
  const x = Math.min(innerWidth - 1, Math.max(0, r.left + r.width / 2))
  const y = Math.min(innerHeight - 1, Math.max(0, r.top + r.height / 2))
  const top = document.elementFromPoint(x, y)
  if (top && top !== el && !el.contains(top) && !top.contains(el)) {
    return `covered by ${top.tagName.toLowerCase()}${top.className ? "." + String(top.className).trim().split(/\s+/)[0] : ""}`
  }
  const backdrop = e => {
    for (; e; e = e.parentElement) {
      const c = getComputedStyle(e).backgroundColor
      if (c && c !== "transparent" && !/rgba\(.*, 0\)$/.test(c)) return c
    }
    return "rgb(255, 255, 255)"
  }
  const color = getComputedStyle(el).color
  if (el.innerText.trim() && color === backdrop(el)) return `text the colour of its background (${color})`
  return "visible"
}

/** The controls a user can reach under `scope`, one line each: role, accessible name, state. */
function controlsIn(scope) {
  const root = document.querySelector(scope) || document.body
  const query = "a[href],button,input:not([type=hidden]),select,textarea,[role=button],[role=link],[role=tab],[role=option],[role=menuitem],[role=checkbox],[role=radio],[role=switch],[role=combobox],[role=textbox],[contenteditable=true]"
  const kinds = {checkbox: "checkbox", radio: "radio", search: "searchbox", button: "button", submit: "button", reset: "button", range: "slider", number: "spinbutton"}
  const roleOf = el => {
    const t = el.tagName
    if (el.getAttribute("role")) return el.getAttribute("role")
    if (t === "A") return "link"
    if (t === "BUTTON") return "button"
    if (t === "SELECT") return el.multiple ? "listbox" : "combobox"
    if (t === "INPUT") return kinds[(el.type || "text").toLowerCase()] ?? "textbox"
    return "textbox"
  }
  const nameOf = el => {
    if (el.getAttribute("aria-label")) return el.getAttribute("aria-label")
    const by = el.getAttribute("aria-labelledby")
    if (by) return by.split(/\s+/).map(id => document.getElementById(id)?.innerText ?? "").join(" ")
    if (el.labels?.length) return el.labels[0].innerText
    if (!["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName) && el.innerText?.trim()) return el.innerText
    return el.placeholder || el.title || ""
  }
  const counts = new Map()
  for (const el of root.querySelectorAll(query)) {
    const r = el.getBoundingClientRect()
    const s = getComputedStyle(el)
    if (!r.width || !r.height || s.visibility === "hidden") continue
    const name = nameOf(el).replace(/\s+/g, " ").trim().slice(0, 50)
    let line = roleOf(el) + (name ? ` "${name}"` : " (no name)")
    if (el.disabled) line += " disabled"
    if (el.getAttribute("aria-haspopup")) line += " opens a " + el.getAttribute("aria-haspopup")
    if (el.tagName === "SELECT") line += " [" + [...el.options].slice(0, 8).map(o => o.text).join("|") + "]"
    if (["INPUT", "TEXTAREA"].includes(el.tagName) && el.type !== "password" && el.value) line += " = " + JSON.stringify(el.value.slice(0, 30))
    counts.set(line, (counts.get(line) ?? 0) + 1)
  }
  const alike = new Map()
  for (const line of [...counts].map(([line, n]) => (n > 1 ? `${line} ×${n}` : line))) {
    const shape = line.replace(/\d+/g, "#")
    alike.set(shape, [...(alike.get(shape) ?? []), line])
  }
  return [...alike.values()].flatMap(g => (g.length >= 3 ? [`${g[0]} … ${g.at(-1).match(/"[^"]*"/)?.[0] ?? ""} (${g.length} alike)`] : g))
}

const shown = expected =>
  expected instanceof RegExp ? String(expected) : typeof expected === "function" ? "(predicate)" : JSON.stringify(expected)

/**
 * Runs a scenario file against the live tab, one line per step.
 *
 * A step's `expect` that does not hold is FAILED: the app did something else, the run goes on.
 * Anything else that throws — a locator that never appears, a navigation that times out — is
 * NOT REACHED: the run stops there and leaves the tab on that state, so the session can carry on
 * by hand from the exact point instead of starting over.
 */
async function runScenario(page, file, only) {
  const scenario = (await import(pathToFileURL(file).href + "?t=" + Date.now())).default
  if (typeof scenario !== "function") die("a scenario file exports `default async ({page, step, expect, net, errors, shot, size}) => {…}`")

  const events = []
  const answered = new WeakSet()
  let cur = 0
  const short = u => {
    const clean = cleanUrl(u)
    try {
      const origin = new URL(page.url()).origin
      return clean.startsWith(origin) ? clean.slice(origin.length) || "/" : clean
    } catch {
      return clean
    }
  }
  page.on("response", r => {
    answered.add(r.request())
    if (TRACKED.has(r.request().resourceType())) events.push({i: cur, k: "net", s: `${r.status()} ${r.request().method()} ${short(r.url())}`})
  })
  page.on("requestfailed", r => {
    if (TRACKED.has(r.resourceType()) && !answered.has(r)) events.push({i: cur, k: "net", s: `ERR ${r.method()} ${short(r.url())} — ${r.failure()?.errorText}`})
  })
  page.on("console", m => {
    if (m.type() === "error") events.push({i: cur, k: "err", s: m.text().slice(0, 300)})
  })
  page.on("pageerror", e => events.push({i: cur, k: "err", s: ("uncaught: " + e.message).slice(0, 300)}))

  const ofStep = async k => {
    await sleep(250)
    return events.filter(e => e.i === cur && e.k === k).map(e => e.s)
  }
  const shot = async name => {
    mkdirSync(SHOTS, {recursive: true})
    const f = path.join(SHOTS, String(name).replace(/[^\w.-]/g, "_") + ".png")
    await page.screenshot({path: f, scale: "css"})
    return f
  }

  const lines = []
  let n = 0
  let stopped = false
  const api = {
    page,
    net: () => ofStep("net"),
    errors: () => ofStep("err"),
    shot,
    seen: async locator => ((await locator.count()) ? locator.first().evaluate(seenBy).catch(() => "not on the page") : "not on the page"),
    size: (width, height) => page.setViewportSize({width, height}),
    async expect(actual, expected, what = "value", {timeout = 3000} = {}) {
      const holds = v =>
        expected instanceof RegExp ? expected.test(String(v))
        : typeof expected === "function" ? Boolean(expected(v))
        : JSON.stringify(v) === JSON.stringify(expected)
      const polled = typeof actual === "function"
      const until = Date.now() + timeout
      const trail = []
      const note = v => {
        const t = JSON.stringify(v) ?? String(v)
        if (trail.at(-1) !== t) trail.push(t)
      }
      let v = polled ? await actual() : actual
      note(v)
      while (polled && !holds(v) && Date.now() < until) {
        await sleep(100)
        v = await actual()
        note(v)
      }
      if (holds(v)) return v
      const saw = trail.slice(-4).map(t => (t.length > 160 ? t.slice(0, 160) + "…" : t)).join(" → ")
      throw new Failed(`${what}: expected ${shown(expected)}, saw ${saw}`)
    },
    async step(name, fn) {
      n++
      if (only && !only.includes(n)) return
      if (stopped) return void lines.push(`skipped      ${n}. ${name}`)
      cur = n
      try {
        const said = await fn()
        lines.push(`ok           ${n}. ${name}${said ? " — " + said : ""}`)
      } catch (err) {
        if (err instanceof Failed) {
          const f = await shot(`step${n}`).catch(() => null)
          lines.push(`FAILED       ${n}. ${name} — ${err.message}${f ? ` · shot ${f}` : ""}`)
          return
        }
        const blocked = String(err?.message).replace(/\x1b\[[0-9;]*m/g, "").split("\n").find(l => l.includes("intercepts pointer events"))
        if (blocked) {
          const f = await shot(`step${n}`).catch(() => null)
          lines.push(`FAILED       ${n}. ${name} — a user cannot click it: ${blocked.trim().replace(/^-\s*/, "")}${f ? ` · shot ${f}` : ""}`)
          return
        }
        stopped = true
        const f = await shot(`step${n}-stopped`).catch(() => null)
        const recent = k => events.filter(e => e.k === k).slice(-5).map(e => e.s).join(" | ")
        lines.push(`NOT REACHED  ${n}. ${name} — ${reason(err)}`, `  stopped at ${page.url()}${f ? ` · shot ${f}` : ""}`)
        if (recent("net")) lines.push(`  last requests: ${recent("net")}`)
        if (recent("err")) lines.push(`  console errors: ${recent("err")}`)
        lines.push("  the tab is left on this state — carry on by hand from here")
      }
    },
  }

  try {
    await scenario(api)
  } catch (err) {
    lines.push(`scenario error outside a step: ${reason(err)}`)
  }
  return lines.join("\n") || "(no steps ran)"
}

async function main() {
  const argv = process.argv.slice(2)
  const cmd = argv.shift()
  if (!cmd || cmd === "help" || cmd === "--help") {
    out(`tab.mjs — one persistent tab: a scenario per check, single commands to dig in

  up [url]                 start a browser if down, open url (default ${BASE})
  attach [port]            adopt an app already serving CDP (Electron); never
                           launches and never kills anything
  down                     kill the browser this tool launched
  status                   is it alive, what url/title
  shim                     install \`tab\` on PATH so every later call is short

  goto <url>               navigate (relative resolves against ${BASE})
  reload
  click <sel> [--nth N]
  fill <sel> <value>
  press <key> [sel]
  hover <sel>
  wait <sel> [--state visible|hidden|attached] [--timeout ms]

  text <sel>               innerText of the first match
  eval <js>                page.evaluate, JSON out
  url                      current url + title
  pages                    list the open page targets (Electron windows)
  use <n>                  drive the page at that index from now on
  logs [--errors] [--grep p] [-n N] [--clear]
  net  [--grep p] [-n N] [--clear]
  ws   [secs] [--reload] [--frames N]   record websocket frames via CDP,
       [--inflate] [--grep p]           including sockets living in a worker;
                                        --inflate decodes permessage-deflate
                                        frames (needs --reload)
  size [WxH|reset]         emulate the viewport; it sticks for every later
                           command until \`size reset\`
  shot [name] [--full]     screenshot → prints path only

  map [selector]           the controls a user can reach, one line each
  seen <sel>               "visible", or why a user would not see it

  run <file.mjs> [--only 2,5] [--slow ms]   a scenario in this tab, one line
                           per step: ok, FAILED (the app did something else,
                           goes on) or NOT REACHED (stops, leaves the tab
                           there); 250 ms per action while headed

Selectors are Playwright's: css, text=Login, role=button[name="Save"], #id.
Artifacts: ${OUT}
Env: TAB_BASE, TAB_PORT, TAB_HEADLESS=1, TAB_TIMEOUT, TAB_BROWSER, TAB_PROFILE, TAB_OUT,
     TAB_MJS (point the shim at a checkout instead of the installed plugin).`)
    return
  }

  if (cmd === "shim") {
    const dir = process.env.TAB_SHIM_DIR ?? path.join(homedir(), ".local", "bin")
    const file = path.join(dir, "tab")
    const target = "'" + HERE.replaceAll("'", "'\\''") + "'"
    mkdirSync(dir, {recursive: true})
    writeFileSync(
      file,
      `#!/bin/sh\nT="\${TAB_MJS:-}"\n[ -f "$T" ] || T=${target}\nexec node "$T" "$@"\n`,
    )
    chmodSync(file, 0o755)
    const onPath = (process.env.PATH ?? "").split(":").includes(dir)
    out(`${file}${onPath ? "" : `\n${dir} is not on PATH — add it, or call tab.mjs by its full path`}`)
    return
  }

  if (cmd === "down") {
    if (ATTACHED) {
      writeState({mode: "launch", page: null})
      out(`detached — the app on port ${PORT} was not started by this tool, close it yourself`)
      return
    }
    try {
      execFileSync("pkill", ["-f", `user-data-dir=${PROFILE}`])
    } catch {}
    writeState({page: null})
    out("browser down")
    return
  }

  if (cmd === "attach") {
    const port = Number(argv[0] ?? PORT)
    writeState({mode: "attach", port, page: null})
    const r = await fetch(`http://127.0.0.1:${port}/json/version`, {signal: AbortSignal.timeout(1500)}).catch(() => null)
    if (!r?.ok) die(`nothing is listening on CDP port ${port} — start the app with --remote-debugging-port=${port}`)
    const info = await r.json()
    out(`attached · port ${port} · ${info.Browser ?? "unknown build"}`)
    return
  }

  if (cmd === "status" && !(await cdpAlive())) {
    out(`${ATTACHED ? "attached app" : "browser"}: down`)
    return
  }

  const started = await ensureBrowser()

  if (cmd === "ws") {
    const frames = Number(flag(argv, "frames", 3))
    const reload = Boolean(flag(argv, "reload", false))
    const inflate = Boolean(flag(argv, "inflate", false))
    const grep = flag(argv, "grep", null)
    const seconds = Math.min(120, Number(flag(argv, "secs", argv[0] ?? 8)) || 8)
    out(await recordWs(seconds, {reload, frames, inflate, grep: grep === true ? null : grep}))
    process.exit(0)
  }

  const chromium = await loadChromium()
  const slowMo = cmd === "run" ? Number(flag(argv, "slow", HEADLESS ? 0 : 250)) || 0 : 0
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`, {slowMo})
  const {ctx, page} = await getPage(browser)
  if (state.size && cmd !== "size") await page.setViewportSize(state.size).catch(() => {})

  const done = s => {
    out(s)
    process.exit(0)
  }

  switch (cmd) {
    case "up": {
      if (ATTACHED) writeState({mode: "launch", page: null})
      await ctx.addInitScript(HOOK)
      const target = abs(argv[0])
      if (started || page.url() === "about:blank" || argv[0]) {
        await page.goto(target, {waitUntil: "domcontentloaded", timeout: 20000})
      }
      rememberBase(target)
      await install(page)
      for (const other of ctx.pages()) {
        if (other !== page && !isRealPage(other.url())) await other.close().catch(() => {})
      }
      done(`${started ? "started" : "already up"} · ${page.url()} · ${await page.title()}`)
      break
    }
    case "status":
      await install(page)
      done(`${ATTACHED ? "attached" : "browser"}: up · ${page.url()} · ${await page.title()}`)
      break
    case "goto": {
      await ctx.addInitScript(HOOK)
      const target = abs(argv[0])
      await page.goto(target, {waitUntil: "domcontentloaded", timeout: 20000})
      rememberBase(target)
      await install(page)
      done(`${page.url()} · ${await page.title()}`)
      break
    }
    case "reload":
      await ctx.addInitScript(HOOK)
      await page.reload({waitUntil: "domcontentloaded", timeout: 20000})
      await install(page)
      done(`${page.url()} · ${await page.title()}`)
      break
    case "url":
      done(`${page.url()} · ${await page.title()}`)
      break
    case "pages": {
      const list = realPages(ctx)
      const lines = []
      for (const [i, p] of list.entries()) {
        lines.push(`${i === list.indexOf(page) ? "*" : " "} ${i}  ${p.url()} · ${await p.title().catch(() => "")}`)
      }
      done(lines.join("\n") || "(no pages)")
      break
    }
    case "use": {
      const n = Number(argv[0])
      const list = realPages(ctx)
      if (!Number.isInteger(n) || !list[n]) die(`no page at index ${argv[0]} — run \`pages\``)
      writeState({page: n})
      done(`${n} · ${list[n].url()} · ${await list[n].title().catch(() => "")}`)
      break
    }
    case "click": {
      const nth = Number(flag(argv, "nth", 0))
      await install(page)
      await page.locator(argv[0]).nth(nth).click()
      done("OK")
      break
    }
    case "hover":
      await install(page)
      await page.locator(argv[0]).first().hover()
      done("OK")
      break
    case "fill":
      await install(page)
      await page.locator(argv[0]).first().fill(argv.slice(1).join(" "))
      done("OK")
      break
    case "press": {
      await install(page)
      const key = argv[0]
      if (argv[1]) await page.locator(argv[1]).first().press(key)
      else await page.keyboard.press(key)
      done("OK")
      break
    }
    case "wait": {
      const waitFor = flag(argv, "state", "visible")
      const timeout = Number(flag(argv, "timeout", TIMEOUT))
      await page.locator(argv[0]).first().waitFor({state: waitFor, timeout})
      done("OK")
      break
    }
    case "text": {
      const t = await page.locator(argv[0]).first().innerText()
      done(t.trim())
      break
    }
    case "eval": {
      await install(page)
      const v = await page.evaluate(`(() => { return (${argv.join(" ")}) })()`)
      done(typeof v === "string" ? v : JSON.stringify(v, null, 0) ?? String(v))
      break
    }
    case "logs":
    case "net": {
      const errorsOnly = flag(argv, "errors", false)
      const grep = flag(argv, "grep", null)
      const clear = flag(argv, "clear", false)
      const n = Number(flag(argv, "n", 40))
      await install(page)
      if (clear) {
        await page.evaluate("window.__tab && window.__tab.clear()")
        done("cleared")
        break
      }
      let list = await page.evaluate("window.__tab ? window.__tab.buf : []")
      list = list.filter(e => (cmd === "net" ? e.k === "net" || e.k === "ws" : e.k === "log"))
      if (errorsOnly) list = list.filter(e => e.lvl === "error" || e.lvl === "warn")
      if (grep && grep !== true) {
        const re = new RegExp(grep, "i")
        list = list.filter(e => re.test(JSON.stringify(e)))
      }
      done(list.length ? fmt(list.slice(-n)) : "(nothing)")
      break
    }
    case "size": {
      if (!argv[0] || argv[0] === "reset") {
        writeState({size: null})
        done("reset · " + (await page.evaluate("innerWidth + 'x' + innerHeight")))
        break
      }
      const [width, height] = argv[0].split("x").map(Number)
      if (!width || !height) die("size takes WxH, e.g. 375x812, or reset")
      writeState({size: {width, height}})
      await page.setViewportSize({width, height})
      done(await page.evaluate("innerWidth + 'x' + innerHeight"))
      break
    }
    case "map": {
      const lines = await page.evaluate(controlsIn, argv[0] ?? "body")
      done(lines.length ? lines.slice(0, 150).join("\n") + (lines.length > 150 ? `\n… +${lines.length - 150} more — scope it: map <selector>` : "") : "(no controls)")
      break
    }
    case "seen": {
      const target = page.locator(argv.join(" "))
      done((await target.count()) ? await target.first().evaluate(seenBy) : "not on the page")
      break
    }
    case "run": {
      const only = flag(argv, "only", null)
      if (!argv[0]) die("run takes a scenario file: run <file.mjs> [--only 2,5]")
      await ctx.addInitScript(HOOK)
      await install(page)
      const list = typeof only === "string" ? only.split(",").map(Number) : null
      done(await runScenario(page, path.resolve(argv[0]), list))
      break
    }
    case "shot": {
      mkdirSync(SHOTS, {recursive: true})
      const full = flag(argv, "full", false)
      const name = (argv[0] ?? "shot").replace(/[^\w.-]/g, "_")
      const file = path.join(SHOTS, name.endsWith(".png") ? name : name + ".png")
      await page.screenshot({path: file, fullPage: Boolean(full), scale: "css"})
      done(file)
      break
    }
    default:
      die(`unknown command: ${cmd} (try: help)`)
  }
}

main().catch(die)
