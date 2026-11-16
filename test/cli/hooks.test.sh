#!/usr/bin/env bash
# hooks/advise.py: both hosts' recorded hook input, fed to the script in
# throwaway repos with plans set up through pipeline.py.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
hook="$repo_root/hooks/advise.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "hooks.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
edit() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b, 1))' "$@"; }
# fire JSON: the script's stdout for that stdin; $rc holds its exit code
fire() { out=$(printf '%s' "$1" | python3 -B "$hook" 2>/dev/null); rc=$?; }
# ctx: additionalContext of the last output ('' when none)
ctx() { printf '%s' "$out" | python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t else "", end="")'; }
claude_edit() { # tool path
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","tool_name":sys.argv[1],"cwd":sys.argv[3],"tool_input":{"file_path":sys.argv[2],"old_string":"a","new_string":"b"}}))' "$@"
}
codex_patch() { # path cwd
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","tool_name":"apply_patch","cwd":sys.argv[2],"tool_input":{"command":"*** Begin Patch\n*** Update File: "+sys.argv[1]+"\n@@\n-a\n+b\n*** End Patch"}}))' "$@"
}

repo=$(mktemp_dir)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git commit -q --allow-empty -m base
mkdir -p .ai-workflow/plans docs/spec
touch docs/spec/build.md
example="$repo_root/skills/run-file/references/example.run.toml"
plans=.ai-workflow/plans

mkplan() { # slug
  cat > "$plans/$1.md" <<P
# Plan: $1

Status: draft · branch \`$1\` · base \`<sha>\`
Prototype: none

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. One — \`waiting\`

Do.
Territory: \`src/\`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: normal — logic

## Done

1. a → b

## Spec

none
P
}
for s in 2026-11-17-b 2026-11-17-a 2026-11-17-m 2026-11-17-d; do mkplan $s; done
for s in b a m; do
  cp "$example" "$plans/2026-11-17-$s.run.toml"
  cli approve "$plans/2026-11-17-$s.md" >/dev/null || fail "approve $s"
done
cli plan status "$plans/2026-11-17-b.md" building --note go >/dev/null || fail "building"
cli plan status "$plans/2026-11-17-m.md" merged --note go >/dev/null || fail "merged"
b="$repo/$plans/2026-11-17-b.md"

# hooks#status-at-start: every start source, both hosts, gives the building plan's status alone
for src in startup resume compact; do
  fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":sys.argv[1],"cwd":sys.argv[2]}))' "$src" "$repo")"
  assert_eq 0 "$rc" "$src exits 0" || exit 1
  c=$(ctx)
  assert_contains "$c" "2026-11-17-b — " "$src: status of the building plan" || exit 1
  assert_contains "$c" "Status: building" "$src: the full status" || exit 1
  case "$c" in *2026-11-17-a*|*2026-11-17-m*|*2026-11-17-d*) fail "$src: only the building plan: $c" ;; esac
  assert_contains "$out" '"hookEventName": "SessionStart"' "$src: the event is named" || exit 1
done
# Codex sends the same fields plus its own; a subdirectory cwd still finds the repo
mkdir -p src/deep
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"compact","cwd":sys.argv[1],"model":"gpt","permission_mode":"default","session_id":"s"}))' "$repo/src/deep")"
assert_contains "$(ctx)" "2026-11-17-b — " "Codex compact from a subdirectory" || exit 1

# hooks#status-at-start: no plan from building to passed → nothing
cli plan status "$plans/2026-11-17-b.md" merged --note go >/dev/null || fail "merge b"
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"startup","cwd":sys.argv[1]}))' "$repo")"
assert_eq "" "$out" "no live plan: nothing" || exit 1
assert_eq 0 "$rc" "no live plan: exit 0" || exit 1
cli plan status "$plans/2026-11-17-b.md" building --note again >/dev/null || fail "building again"

# hooks#status-at-start: a live plan with no state file (pre-5.1) is handed over with the CLI's fix line; a draft stays out
mkplan 2026-11-01-old; edit "$plans/2026-11-01-old.md" 'Status: draft' 'Status: building'
mkplan 2026-11-01-new
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"compact","cwd":sys.argv[1]}))' "$repo")"
c=$(ctx)
assert_contains "$c" "2026-11-01-old — no state — fix: run" "stateless live plan reaches the model" || exit 1
assert_contains "$c" "2026-11-17-b — " "the stateful plan is still there" || exit 1
case "$c" in *2026-11-01-new*) fail "a draft stays out: $c" ;; esac
rm "$plans/2026-11-01-old.md" "$plans/2026-11-01-new.md"

# hooks#edit-names-command: Claude Code edits of the building plan
edit "$b" 'Status: building' 'Status: passed'
fire "$(claude_edit Edit "$b" "$repo")"
assert_contains "$(ctx)" "pipeline.py plan status" "a Status edit names plan status" || exit 1
assert_contains "$out" '"hookEventName": "PostToolUse"' "the event is named" || exit 1
edit "$b" 'Status: passed' 'Status: building'
edit "$b" '### 1. One — `waiting`' '### 1. One — `done`'
fire "$(claude_edit Write "$b" "$repo")"
assert_contains "$(ctx)" "phase start" "a phase heading edit names phase start / phase done" || exit 1
assert_contains "$(ctx)" "phase done" "a phase heading edit names phase done" || exit 1
edit "$b" '### 1. One — `done`' '### 1. One — `waiting`'
edit "$b" 'A.' 'Approach changed.'
fire "$(claude_edit Edit "$b" "$repo")"
assert_contains "$(ctx)" "pipeline.py approve" "an Approach edit names approve" || exit 1
edit "$b" 'Approach changed.' 'A.'
fire "$(claude_edit Edit "$b" "$repo")"
assert_eq "" "$out" "no drift: nothing" || exit 1

# hooks#edit-names-command: Codex apply_patch on notes, judge and state files
for k in notes judge; do
  : > "$plans/2026-11-17-b.$k.md"
  fire "$(codex_patch "$plans/2026-11-17-b.$k.md" "$repo")"
  case $k in
    notes) assert_contains "$(ctx)" "note add|edit|drop" "notes file: names the note commands" || exit 1 ;;
    judge) assert_contains "$(ctx)" "first verdict" "judge file: names the first verdict" || exit 1 ;;
  esac
done
fire "$(claude_edit Write "$repo/$plans/2026-11-17-b.json" "$repo")"
assert_contains "$(ctx)" "only through \`pipeline.py\` commands" "state file: only through commands" || exit 1
fire "$(codex_patch "$b" "$repo")"
assert_eq 0 "$rc" "Codex patch of a clean plan exits 0" || exit 1
assert_eq "" "$out" "Codex patch of a clean plan: nothing" || exit 1

# hooks#edit-names-command: a draft, a run file, other paths → nothing
for p in "$plans/2026-11-17-d.md" "$plans/2026-11-17-b.run.toml" src/a.py "$plans/2026-11-17-b.gate-log.md"; do
  fire "$(claude_edit Edit "$repo/$p" "$repo")"
  assert_eq "" "$out" "$p: nothing" || exit 1
  assert_eq 0 "$rc" "$p: exit 0" || exit 1
done

# hooks#advise-only: failures print nothing and exit 0
outside=$(mktemp_dir)
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"startup","cwd":sys.argv[1]}))' "$outside")"
assert_eq "" "$out" "SessionStart outside a repository: nothing" || exit 1
assert_eq 0 "$rc" "SessionStart outside a repository: exit 0" || exit 1
fire "$(claude_edit Edit "$outside/x.md" "$outside")"
assert_eq "" "$out" "PostToolUse outside a repository: nothing" || exit 1
assert_eq 0 "$rc" "PostToolUse outside a repository: exit 0" || exit 1
fire 'not json {'
assert_eq "" "$out" "malformed JSON: nothing" || exit 1
assert_eq 0 "$rc" "malformed JSON: exit 0" || exit 1
fire '{"hook_event_name":"PostToolUse","tool_input":"x"}'
assert_eq 0 "$rc" "tool_input of the wrong shape: exit 0" || exit 1
printf '{broken' > "$plans/2026-11-17-b.json"
fire "$(claude_edit Edit "$b" "$repo")"
assert_eq "" "$out" "corrupt state, plan edit: nothing" || exit 1
assert_eq 0 "$rc" "corrupt state, plan edit: exit 0" || exit 1
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"startup","cwd":sys.argv[1]}))' "$repo")"
assert_eq 0 "$rc" "corrupt state, session start: exit 0" || exit 1

# hooks#advise-only: hooks.json declares the two events only, no blocking
python3 - "$repo_root/hooks/hooks.json" <<'P' || fail "hooks.json shape"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
assert sorted(h) == ["PostToolUse", "SessionStart"], sorted(h)
assert h["SessionStart"][0]["matcher"] == "startup|resume|compact"
assert h["PostToolUse"][0]["matcher"].split("|") == ["Write", "Edit", "MultiEdit", "apply_patch"]
P

echo ok
