#!/usr/bin/env bash
# Normalized advice and native hook input, fed to the scripts in
# throwaway repos with plans set up through pipeline.py.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
hook="$repo_root/adapters/hooks.py"
advice="$repo_root/hooks/advise.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "hooks.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
. "$repo_root/test/cli/lifecycle.sh"
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
normalized_start() {
  python3 -c 'import json,sys; print(json.dumps({"event":"session_start","cwd":sys.argv[1]}))' "$1" | python3 -B "$advice"
}

repo=$(mktemp_dir)
cd "$repo" || exit 1
repo=$(pwd -P)
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git commit -q --allow-empty -m base
mkdir -p .runweld/workflow/plans docs/spec
touch docs/spec/build.md
example="$repo_root/skills/run-file/references/example.run.toml"
plans=.runweld/workflow/plans

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
  if [ "$s" = m ]; then
    edit "$plans/2026-11-17-$s.md" 'Status: draft' 'Status: merged'
    cli approve "$plans/2026-11-17-$s.md" >/dev/null || fail "adopt completed history"
  else
    approve_plan "$plans/2026-11-17-$s.md" >/dev/null || fail "approve $s"
  fi
done
a="$repo/$plans/2026-11-17-a.md"
b="$repo/$plans/2026-11-17-b.md"
base=$(git rev-parse HEAD)
linked="$repo/build tree"
cli build start "$b" --base "$base" --worktree "$linked" >/dev/null || fail "building in a real worktree"
cli phase start "$b" 1 >/dev/null || fail "open linked phase"

# hooks#status-at-start: normalized input returns plain advice without a native envelope.
out=$(normalized_start "$repo")
assert_contains "$out" "Status: building" "normalized lifecycle advice" || exit 1
assert_contains "$out" "Workflow for $a" "hooks#status-at-start: approved plan awaiting a separate start is visible by path" || exit 1
assert_contains "$out" "Workflow for $b" "hooks#status-at-start: building plan has its own path" || exit 1
assert_contains "$out" "Coordinator — Wait for the user's separate start instruction" "hooks#status-at-start: approved plan explains the wait" || exit 1
assert_eq "$out" "$(cli status --current)" "hooks#status-at-start: main checkout advice is current CLI status" || exit 1
case "$out" in *hookSpecificOutput*) fail "common advice must not wrap native output" ;; esac

# hooks#status-at-start build#workflow-progress: only the relevant run is shown from a linked checkout.
mkdir -p "$linked/src/deep"
out=$(normalized_start "$linked/src/deep")
assert_contains "$out" "Workflow for $b" "hooks#status-at-start: the linked checkout discovers the plan stored in the main checkout" || exit 1
assert_contains "$out" "Build — current" "hooks#status-at-start: resume shows the current stage" || exit 1
assert_contains "$out" "Implementer for phase 1 — Work from the phase brief" "hooks#status-at-start: resume names the owner and action" || exit 1
assert_eq "$(cli status "$b")" "$out" "hooks#status-at-start: linked advice matches explicit plan status" || exit 1
assert_eq "$out" "$(cd "$linked/src/deep" && cli status --current)" "hooks#status-at-start: linked advice matches current CLI status" || exit 1
assert_eq "[$(cli status "$b" --json)]" "$(cd "$linked" && cli status --current --json)" "build#workflow-progress: current JSON contains the same linked plan and workflow" || exit 1
assert_contains "$(cd "$linked" && cli status)" "2026-11-17-b — building" "build#workflow-progress: the existing CLI inventory finds the main checkout's plan" || exit 1

other="$repo/other tree"
git worktree add -q -b unrelated "$other" "$base" || fail "create unrelated worktree"
assert_eq "" "$(normalized_start "$other")" "hooks#status-at-start: an unrelated checkout is quiet" || exit 1
assert_eq "" "$(cd "$other" && cli status --current)" "hooks#status-at-start: current CLI status is quiet in an unrelated checkout" || exit 1

# hooks#advise-only: malformed normalized input stays quiet.
for payload in '{"event":"unknown","paths":[]}' '{"event":"edit","paths":"bad"}' '[]' 'not json'; do
  out=$(printf '%s' "$payload" | python3 -B "$advice")
  assert_eq 0 "$?" "malformed normalized advice exits 0" || exit 1
  assert_eq "" "$out" "malformed normalized advice is quiet" || exit 1
done

# hooks#status-at-start: every start source, both hosts, gives current status
for src in startup resume compact; do
  fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":sys.argv[1],"cwd":sys.argv[2]}))' "$src" "$repo")"
  assert_eq 0 "$rc" "$src exits 0" || exit 1
  c=$(ctx)
  assert_contains "$c" "2026-11-17-b — " "$src: status of the building plan" || exit 1
  assert_contains "$c" "Status: building" "$src: the full status" || exit 1
  assert_contains "$c" "Workflow for $a" "$src: status of the approved plan" || exit 1
  case "$c" in *2026-11-17-m*|*2026-11-17-d*) fail "$src: merged and draft plans stay out: $c" ;; esac
  assert_contains "$out" '"hookEventName": "SessionStart"' "$src: the event is named" || exit 1
done
# Codex sends the same fields plus its own; a subdirectory cwd still finds the repo
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"compact","cwd":sys.argv[1],"model":"gpt","permission_mode":"default","session_id":"s"}))' "$linked/src/deep")"
assert_contains "$(ctx)" "2026-11-17-b — " "Codex compact from a subdirectory" || exit 1
assert_eq "$(cli status "$b")" "$(ctx)" "hooks#status-at-start: native compact selects the linked plan" || exit 1

# hooks#status-at-start: a live plan with no state file is handed over with the CLI's fix line; a draft stays out
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
edit "$b" '### 1. One — `in progress`' '### 1. One — `done`'
fire "$(claude_edit Write "$b" "$repo")"
assert_contains "$(ctx)" "phase start" "a phase heading edit names phase start / phase done" || exit 1
assert_contains "$(ctx)" "phase done" "a phase heading edit names phase done" || exit 1
edit "$b" '### 1. One — `done`' '### 1. One — `in progress`'
edit "$b" 'A.' 'Approach changed.'
fire "$(claude_edit Edit "$b" "$repo")"
assert_contains "$(ctx)" "pipeline.py approve" "an Approach edit names approve" || exit 1
edit "$b" 'Approach changed.' 'A.'
fire "$(claude_edit Edit "$b" "$repo")"
assert_eq "" "$out" "no drift: nothing" || exit 1

# hooks#edit-names-command: normalized paths are relative to the event's cwd.
out=$(python3 -c 'import json,sys; print(json.dumps({"event":"edit","cwd":sys.argv[1],"paths":[".runweld/workflow/plans/2026-11-17-b.notes.md"]}))' "$repo" | python3 -B "$advice")
assert_contains "$out" "note add|edit|drop" "normalized relative edit" || exit 1
# hooks#advise-only: an unrelated event cannot interpret otherwise valid edit paths.
out=$(python3 -c 'import json,sys; print(json.dumps({"event":"unknown","cwd":sys.argv[1],"paths":[".runweld/workflow/plans/2026-11-17-b.notes.md"]}))' "$repo" | python3 -B "$advice")
assert_eq "" "$out" "unrelated normalized event is quiet" || exit 1
# hooks#advise-only: unrelated native tools cannot become edit advice.
fire "$(claude_edit Bash "$repo/$plans/2026-11-17-b.json" "$repo")"
assert_eq "" "$out" "unrelated native tool is quiet" || exit 1

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
cp "$plans/2026-11-17-b.json" "$repo/state-backup.json"
printf '{broken' > "$plans/2026-11-17-b.json"
fire "$(claude_edit Edit "$b" "$repo")"
assert_eq "" "$out" "corrupt state, plan edit: nothing" || exit 1
assert_eq 0 "$rc" "corrupt state, plan edit: exit 0" || exit 1
fire "$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"startup","cwd":sys.argv[1]}))' "$repo")"
assert_eq 0 "$rc" "corrupt state, session start: exit 0" || exit 1

mv "$repo/state-backup.json" "$plans/2026-11-17-b.json"

# hooks#edit-names-command: each declared registration resolves with only its native root.
python3 -B - "$repo_root" "$repo" <<'P' || fail "native registration fixtures"
import json, os, pathlib, subprocess, sys
root, cwd = map(pathlib.Path, sys.argv[1:])
variables = ('CLAUDE_PLUGIN_ROOT', 'PLUGIN_ROOT', 'QODER_PLUGIN_ROOT')
base_env = {k: v for k, v in os.environ.items() if k not in variables}
for host, variable in zip(('claude', 'codex', 'qoder'), variables):
    manifest = json.loads((root / f'.{host}-plugin/plugin.json').read_text())
    hooks = json.loads((root / manifest['hooks']).read_text())['hooks']
    assert sorted(hooks) == ['PostToolUse', 'SessionStart']
    assert hooks['SessionStart'][0]['matcher'] == 'startup|resume|compact'
    assert hooks['PostToolUse'][0]['matcher'].split('|') == ['Write', 'Edit', 'MultiEdit', 'apply_patch']
    payloads = [
        ({'hook_event_name': 'PostToolUse', 'tool_name': 'Write', 'cwd': str(cwd),
          'tool_input': {'file_path': '.runweld/workflow/plans/2026-11-17-b.notes.md'}}, 'note add|edit|drop'),
        ({'hook_event_name': 'SessionStart', 'source': 'startup', 'cwd': str(cwd)}, '2026-11-17-b'),
    ]
    for payload, expected in payloads:
        command = hooks[payload['hook_event_name']][0]['hooks'][0]['command']
        result = subprocess.run(['bash', '-c', command], input=json.dumps(payload), cwd=cwd,
                                env=dict(base_env, **{variable: str(root)}), text=True, capture_output=True)
        assert result.returncode == 0 and not result.stderr, (host, result)
        assert expected in json.loads(result.stdout)['hookSpecificOutput']['additionalContext'], (host, result)
        for bad in ('not json', '[]', '{"hook_event_name":"unrelated"}'):
            result = subprocess.run(['bash', '-c', command], input=bad, cwd=cwd,
                                    env=dict(base_env, **{variable: str(root)}), text=True, capture_output=True)
            assert result.returncode == 0 and not result.stdout and not result.stderr, (host, result)
        result = subprocess.run(['bash', '-c', command], input=json.dumps(payload), cwd=cwd,
                                env=dict(base_env, **{variable: str(root / 'missing')}), text=True, capture_output=True)
        assert result.returncode == 0 and not result.stdout and not result.stderr, (host, result)
P

echo ok
