#!/usr/bin/env bash
# PreToolUse(Bash) — enforce the commit-work skill on git commits.
#   * deny blanket staging (git add . / -A / --all)
#   * deny commits carrying banned trailers or a non-Conventional subject
#   * deny a subject over 72 chars or a body over 300 chars
#   * inject the commit-work rules as context on every git commit
# Fail-open: on any parsing error the command is allowed (never blocks work by accident).

input="$(cat 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null
  exit 0
}

# 1) Blanket staging — stage intentionally, never `git add .`/`-A`/`--all`.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|\.)($|[[:space:]]|[;&|])'; then
  deny "Blocked: blanket staging (git add . / -A / --all). Stage intentionally with 'git add -p' or explicit paths so only intended changes land."
fi

# 1b) The same thing wearing a different hat: `git commit -a` stages every tracked
# modification, including work another agent is halfway through. Matches the
# combined short forms (-am, -av) and the long option, but not `--amend`.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+commit[[:space:]]+([^[:space:]]*[[:space:]]+)*(-[[:alnum:]]*a[[:alnum:]]*|--all)([[:space:]]|=|$)'; then
  deny "Blocked: 'git commit -a' stages every tracked modification, including a file another agent is mid-edit on. Stage the paths you changed yourself, then commit."
fi

# Everything below concerns git commit only.
printf '%s' "$cmd" | grep -qE 'git[[:space:]]+commit' || exit 0

# 2) Banned trailers anywhere in the command (case-insensitive).
if printf '%s' "$cmd" | grep -qiE 'Co-Authored-By|Generated with Claude Code|Claude-Session:|🤖'; then
  deny "Blocked by commit-work: banned trailer present (Co-Authored-By / 'Generated with Claude Code' / Claude-Session). Remove it and retry."
fi

# 3) Pull the commit message out of the command, whatever shape it arrives in.
#    Two forms cover everything in practice: a quoted heredoc (`-F - <<'EOF' … EOF`,
#    which every multi-line message uses) and a single-line `-m "…"`. The heredoc
#    form used to slip past this hook entirely — and it is the form long messages
#    arrive in, so the checks below never saw the commits they were written for.
#    Anything we cannot parse leaves msg empty and every check is skipped.
msg="$(printf '%s' "$cmd" | awk -v Q="'" '
  d == "" {
    p = index($0, "<<")
    if (p == 0) next
    rest = substr($0, p + 2)
    if (substr(rest, 1, 1) == "-") rest = substr(rest, 2)
    ch = substr(rest, 1, 1)
    if (ch != Q && ch != "\"") next
    rest = substr(rest, 2)
    e = index(rest, ch)
    if (e > 1) d = substr(rest, 1, e - 1)
    next
  }
  $0 == d { exit }
  { print }
' 2>/dev/null || true)"

if [ -z "$msg" ]; then
  msg="$(printf '%s' "$cmd" | grep -oE "\-m[[:space:]]+\"[^\"]*\"|\-m[[:space:]]+'[^']*'" | head -1 | sed -E "s/^-m[[:space:]]+[\"']//; s/[\"']$//" 2>/dev/null || true)"
fi

# Characters, not bytes: a Cyrillic subject would otherwise measure double and be
# refused for a length it does not have.
chars() {
  n="$(printf '%s' "$1" | LC_ALL=en_US.UTF-8 wc -m 2>/dev/null | tr -d '[:space:]')"
  case "$n" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$n" ;; esac
}

if [ -n "$msg" ]; then
  subject="$(printf '%s\n' "$msg" | sed -n '1p')"

  # 3a) Conventional Commits subject.
  if ! printf '%s' "$subject" | grep -qE '^(([A-Z][A-Z0-9]*-[0-9]+|#[0-9]+):?[[:space:]]+)?(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9._/-]+\))?!?: .+'; then
    deny "Blocked by commit-work: subject is not Conventional Commits ('$subject'). Use 'type(scope): summary' (an optional leading ticket prefix like 'ABC-123:' or '#123' is allowed) — type in feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert."
  fi

  # 3b) Subject length. The 72-char limit has been in the rules all along and was
  # never enforced, so it held about three quarters of the time.
  slen="$(chars "$subject")"
  if [ "$slen" -gt 72 ]; then
    deny "Blocked by commit-work: subject is $slen chars, the cap is 72. Say the one thing that changed and move the rest into the body — or split the commit."
  fi

  # 3c) Body length. The old rule was 2-4 sentences, which is not a length: bodies
  # obeyed it and still ran past 300 characters. The cap is now the length itself.
  body="$(printf '%s\n' "$msg" | sed '1d' | awk 'NF { p = 1 } p { a[++n] = $0 } END { while (n && a[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print a[i] }')"
  blen="$(chars "$body")"
  if [ "$blen" -gt 300 ]; then
    deny "Blocked by commit-work: body is $blen chars, the cap is 300. Most commits need no body at all — write one only when the subject leaves a real question open, then say why it changed and what the diff cannot show. Cut anything the diff already shows, file lists, and the subject restated in longer words."
  fi
fi

# 4) Clean git commit — inject the commit-work rules as context.
jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"commit-work rules in force: stage only intended changes (verify with git diff --cached), run the fastest relevant check. Subject: Conventional Commits, 72 characters max — enforced, a longer one is refused. Body: default to none, and write one only when the subject leaves a real question open; then 300 characters max — enforced, a longer one is refused. A body says WHY plus what the diff cannot show — never a file list, never the diff read aloud. Simple programming English, B1 level, short active sentences; use/add/remove/fix/so/because, not leverage/utilize/facilitate/thereby/whilst/hence; no marketing adjectives (seamless, robust, comprehensive). Technical terms stay exact. No Co-Authored-By / Claude footnote / Claude-Session trailer."}}' 2>/dev/null
exit 0
