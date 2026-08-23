# Commit message template (Conventional Commits)

```text
<type>(<scope>): <summary>

<Why it changed, plus anything the diff cannot show.>
```

## Size

Both caps are enforced by the `commit-guard` hook. A message over either one is
refused, not warned about.

- Subject ≤ 72 characters, imperative, no trailing period.
- Default to no body. Write one only if the subject leaves a real question open.
- When you write one: ≤ 300 characters, wrapped at 72 columns — about two short
  sentences.
- Second paragraph only for a separate fact — a caveat, a side effect, a
  follow-up. Not for more detail on the first one, and inside the same 300.
- If 300 characters cannot hold the reason, the commit is too big. Split it
  instead.

Compact is the target, not terse. Keep every fact a reviewer needs; drop every
word they do not.

## What belongs in the body

Keep:

- why the change was needed
- the symptom it fixes, and the exact error text if there was one
- the constraint that forced this shape over an obvious alternative
- a consequence a reader would miss

Cut:

- anything the diff already shows
- file-by-file or function-by-function lists
- "This commit …", "In this change we …"
- the subject said again in longer words
- praise for your own change: cleaner, more robust, much better

## Language: simple programming English

Write for a reader at B1 English. Short sentences, one idea each, active voice.
Present tense for how the code behaves now; past tense only for how it behaved
before.

Technical terms stay exact — `race condition`, `debounce`, `idempotent`,
`symlink`, `backpressure`, `stale closure`. Those are precise, not fancy. The
rule is about the prose around them.

| Do not write | Write |
| --- | --- |
| leverage, utilize | use |
| facilitate, enable (as prose) | let, help |
| ensure | make sure |
| mitigate | reduce |
| surface (verb) | show, report |
| introduce | add |
| eliminate | remove |
| prior to | before |
| in order to | to |
| subsequently, thereafter | then |
| thereby, hence, thus | so |
| whilst | while |
| albeit | though |
| aforementioned | this, that |
| myriad, plethora | many |
| obviate | remove the need for |
| expedite | speed up |
| perform a check | check |
| is responsible for | does, handles |

No metaphors, no marketing adjectives: seamless, robust, comprehensive,
streamlined, powerful, elegant.

## Good / bad

Too long, and most of it is the diff read aloud — 463 characters, refused by the
hook:

```text
fix(auth): resolve token expiration edge case

This commit refactors the token validation logic in src/api/auth.js. We
introduce a new constant GRACE_PERIOD_MS set to 5000 and leverage it within
the validateToken function, thereby ensuring that tokens which have recently
expired are still accepted. Additionally, the comparison operator has been
changed from < to <= and the associated unit tests in auth.test.js have been
updated accordingly to cover the new behaviour, making the auth flow much
more robust.
```

Same commit, compact — 227 characters:

```text
fix(auth): accept tokens for 5s past expiry

Clock skew between the API and the auth service made valid tokens fail
right at the boundary, so users hit a random 401 on refresh. A 5s grace
period is shorter than the 30s refresh window, so no token outlives its
own refresh.
```

Subject alone is enough — no body:

```text
chore(deps): bump vitest to 3.2.4
```

Second paragraph earns its place, because it is a separate fact:

```text
feat(zsh): source fzf key bindings and completion

fzf was installed but never sourced, so Ctrl+R and Ctrl+T did nothing.

Guarded on `[ -t 0 ]`, not just on the file existing: both scripts set up
ZLE widgets, and with no terminal attached zsh prints "can't change option:
zle" on stderr.
```

## Other rules

- Breaking change: `!` in the header and/or a `BREAKING CHANGE:` footer.
- No `Co-Authored-By`, no "Generated with Claude Code" footnote, no
  `Claude-Session:` trailer.
