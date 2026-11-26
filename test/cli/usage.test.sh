#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

usage="$repo_root/scripts/usage"

fail() {
  echo "usage.test.sh: $1" >&2
  exit 1
}

root=$(mktemp_dir)
proj="$root/-Users-me-Documents-Projects-demo"
mkdir -p "$proj/sess-a/subagents" "$root/-Users-me-other"
cat > "$proj/sess-a.jsonl" <<'JSONL'
{"type":"ai-title","aiTitle":"Demo session"}
{"type":"user","timestamp":"2026-09-25T10:00:00Z","message":{"role":"user","content":"hello"}}
{"type":"assistant","timestamp":"2026-09-25T10:05:00Z","message":{"id":"m1","role":"assistant","usage":{"output_tokens":2600,"input_tokens":1000,"cache_read_input_tokens":400000,"cache_creation_input_tokens":100000},"content":[{"type":"tool_use","name":"Skill","input":{"skill":"runweld grill"}}]}}
{"type":"assistant","timestamp":"2026-09-25T10:05:00Z","message":{"id":"m1","role":"assistant","usage":{"output_tokens":2600,"input_tokens":1000,"cache_read_input_tokens":400000,"cache_creation_input_tokens":100000},"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"Explore"}}]}}
{"type":"assistant","timestamp":"2026-09-25T10:06:00Z","message":{"id":"m2","role":"assistant","usage":{"output_tokens":900,"input_tokens":1000},"content":[{"type":"tool_use","name":"Task","input":{}},{"type":"tool_use","name":"Bash","input":"not a dict"}]}}
{"type":"user","timestamp":"2026-09-25T10:07:00Z","message":{"role":"user","content":[{"type":"tool_result","content":"done"},{"type":"text","text":"tool text"}]}}
{"type":"user","timestamp":"2026-09-25T10:08:00Z","isMeta":true,"message":{"role":"user","content":"meta text"}}
{"type":"user","timestamp":"2026-09-25T10:09:00Z","message":{"role":"user","content":"<system-reminder>injected</system-reminder>"}}
{"type":"user","timestamp":"2026-09-25T10:10:00Z","message":{"role":"user","content":"<command-name>/grill</command-name><command-args>an idea</command-args>"}}
null
[1]
{"type":"user","timestamp":12345,"message":{"role":"user","content":[{"type":"text","text":null}]}}
{"type":"user","timestamp":"2026-09-25T10:24:00Z","message":{"role":"user","content":"[Request interrupted by user]"}}
{"type":"user","timestamp":"2026-09-25T10:39:00Z","message":{"role":"user","content":"second"}}
{"type":"assistant","timestamp":"2026-09-25T10:55:00Z","message":{"id":"m3","role":"assistant","usage":{"output_tokens":null}}}
{"type":"user","timestamp":"2026-09-25T12:55:00Z","isSidechain":true,"message":{"role":"user","content":"from a sidechain"}}
JSONL
cat > "$proj/sess-a/subagents/agent-s1.jsonl" <<'JSONL'
{"type":"assistant","timestamp":"2026-09-25T10:06:00Z","message":{"id":"a1","role":"assistant","usage":{"output_tokens":2}}}
{"type":"assistant","timestamp":"2026-09-25T10:42:00Z","message":{"id":"a1","role":"assistant","stop_reason":"end_turn","usage":{"output_tokens":3000}}}
JSONL
printf '{"agentType":"Explore"}\n' > "$proj/sess-a/subagents/agent-s1.meta.json"
cat > "$proj/sess-old.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-08-01T10:00:00Z","message":{"role":"user","content":"old"}}
JSONL
cat > "$proj/sess-c.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-09-24T10:00:00Z","message":{"role":"user","content":"c one"}}
{"type":"user","timestamp":"2026-09-24T10:07:00Z","message":{"role":"user","content":"c two"}}
{"type":"user","timestamp":"2026-09-24T10:14:00Z","message":{"role":"user","content":"c three"}}
{"type":"user","timestamp":"2026-09-24T10:21:00Z","message":{"role":"user","content":[{"type":"text"}]}}
JSONL
cat > "$root/-Users-me-other/sess-b.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-09-25T09:00:00Z","message":{"role":"user","content":"elsewhere"}}
JSONL

out=$("$usage" --source claude --root "$root" --project demo --since 2026-09-25 --json)
assert_exit 0 "TC-1: --json exits 0" || fail "TC-1"
field() { printf '%s' "$out" | python3 -c "import json,sys; r=json.load(sys.stdin); print(len(r) if '$1'=='count' else r[0]['$1'])"; }
assert_eq 1 "$(field count)" "TC-1: --project and --since (inclusive) leave one session" || fail "TC-1: $out"
assert_eq "Demo session" "$(field title)" "TC-2: the title" || fail "TC-2"
assert_eq 0.9 "$(field wall_h)" "TC-2: wall hours leave out sidechain events" || fail "TC-2"
assert_eq 0.4 "$(field active_h)" "TC-2: active hours count gaps under 15 minutes only" || fail "TC-2"
assert_eq 3 "$(field nuser)" "TC-2: human messages: not tool results, meta, injected tags, interrupts, sidechains" || fail "TC-2"
assert_eq 1 "$(field interrupts)" "TC-2: interrupts" || fail "TC-2"
assert_eq "{'grill': 1}" "$(field cmds)" "TC-2: slash commands" || fail "TC-2"
assert_eq 3 "$(field out_k)" "TC-2: output tokens once per message, floored to thousands" || fail "TC-2"
assert_eq 0.5 "$(field in_M)" "TC-2: input tokens include the cache, once per message" || fail "TC-2"
assert_eq "{'runweld grill': 1}" "$(field skills)" "TC-2: skills" || fail "TC-2"
assert_eq "{'Explore': 1, '?': 1}" "$(field agents)" "TC-2: Agent and Task dispatches" || fail "TC-2"
assert_eq 1 "$(field nsubs)" "TC-2: subagents counted by transcript, not by meta file" || fail "TC-2"
assert_eq 3 "$(field sub_out_k)" "TC-2: subagent output tokens once per message, at the streamed final count" || fail "TC-2"
assert_eq 0.6 "$(field sub_h)" "TC-2: subagent hours" || fail "TC-2"

printf '%s' "$out" | python3 -c '
import json, sys
assert json.load(sys.stdin) == [{"project": "-Users-me-Documents-Projects-demo", "sid": "sess-a", "title": "Demo session", "start": "2026-09-25 10:00", "wall_h": 0.9, "active_h": 0.4, "nuser": 3, "interrupts": 1, "skills": {"runweld grill": 1}, "cmds": {"grill": 1}, "agents": {"Explore": 1, "?": 1}, "out_k": 3, "in_M": 0.5, "nsubs": 1, "sub_out_k": 3, "sub_h": 0.6}]
' || fail "usage#measurements-preserved: complete Claude record"

claude_json=$out
mkdir -p "$root/unrelated/bad.jsonl"
out=$("$usage" --source claude --root "$root" --project demo --since 2026-09-25 --json 2>&1)
assert_exit 0 "usage#measurements-preserved: project filter skips unrelated unreadable transcripts" || fail "$out"
assert_eq "$claude_json" "$out" "usage#measurements-preserved: project filter output" || fail "$out"
rmdir "$root/unrelated/bad.jsonl" "$root/unrelated"

mkdir -p "$root/claude-home/.claude"
ln -s "$root" "$root/claude-home/.claude/projects"
out=$(HOME="$root/claude-home" "$usage" --source claude --project demo --since 2026-09-25 --json)
assert_exit 0 "usage#measurements-preserved: selected Claude native root" || fail "$out"
assert_eq "$claude_json" "$out" "usage#measurements-preserved: native root matches explicit root" || fail "$out"

msgs="$root/msgs.txt"
out=$("$usage" --source claude --root "$root" --messages "$msgs")
assert_exit 0 "TC-3: the table exits 0" || fail "TC-3"
assert_contains "$out" "project	sessions	wall_h	active_h	nuser	out_k	nsubs	sub_h" "TC-3: the header" || fail "TC-3: $out"
assert_contains "$out" "-Users-me-Documents-Projects-demo	3	1.3	0.8	8	3	1	0.6" "TC-3: the demo row sums exact values" || fail "TC-3: $out"
assert_contains "$out" "-Users-me-other	1	0.0	0.0	1	0	0	0.0" "TC-3: one row per project" || fail "TC-3: $out"
body=$(cat "$msgs")
assert_eq "=== -Users-me-Documents-Projects-demo sess-old 2026-08-01 10:00
old
=== -Users-me-Documents-Projects-demo sess-c 2026-09-24 10:00
c one
=== -Users-me-Documents-Projects-demo sess-c 2026-09-24 10:07
c two
=== -Users-me-Documents-Projects-demo sess-c 2026-09-24 10:14
c three
=== -Users-me-Documents-Projects-demo sess-c 2026-09-24 10:21

=== -Users-me-Documents-Projects-demo sess-a 2026-09-25 10:00
hello
=== -Users-me-Documents-Projects-demo sess-a 2026-09-25 10:10
CMD /grill an idea
=== -Users-me-Documents-Projects-demo sess-a 2026-09-25 10:39
second
=== -Users-me-other sess-b 2026-09-25 09:00
elsewhere" "$body" "usage#measurements-preserved: exact Claude message export" || fail "$body"
assert_contains "$body" "hello" "TC-3: human messages are written" || fail "TC-3"
assert_contains "$body" "CMD /grill an idea" "TC-3: a slash command is written as a message" || fail "TC-3"
for skipped in "tool text" "meta text" "injected" "from a sidechain"; do
  ! printf '%s' "$body" | grep -qF "$skipped" || fail "TC-3: '$skipped' should not be a human message"
done
[ "$(printf '%s\n' "$body" | grep -n 'hello' | cut -d: -f1)" -lt "$(printf '%s\n' "$body" | grep -n 'second' | cut -d: -f1)" ] \
  || fail "TC-3: messages are in time order"

"$usage" --source claude --root "$root/missing" >/dev/null 2>&1
assert_exit 2 "TC-4: a missing root exits 2" || fail "TC-4"
"$usage" --source claude --root "$root" --since 2026-9-1 >/dev/null 2>&1
assert_exit 2 "TC-4b: a malformed --since exits 2" || fail "TC-4b"
"$usage" --source claude --root "$root" --messages "$root/no/such/dir/m.txt" >/dev/null 2>&1
assert_exit 2 "TC-4c: --messages into a missing directory exits 2" || fail "TC-4c"

pipe_err="$root/pipe.err"
"$usage" --source claude --root "$root" --json 2>"$pipe_err" | true
[ ! -s "$pipe_err" ] || fail "TC-5: a closed pipe prints nothing on stderr: $(cat "$pipe_err")"

codex_home="$root/codex"
python3 - "$codex_home/sessions" <<'PYFIXTURE'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1]) / "2026/09/25"
root.mkdir(parents=True)

def event(kind, payload, minute=0):
    return {"timestamp": f"2026-09-25T10:{minute:02}:00Z", "type": kind, "payload": payload}

def meta(sid, **extra):
    return event("session_meta", {"id": sid, "timestamp": "2026-09-25T10:00:00Z", "cwd": "/work/demo", **extra})

def message(mid, text, kind="user.text", minute=1):
    return event("response_item", {"type": "message", "role": "user", "id": mid,
        "content": [{"type": "input_text", "text": text}],
        "internal_chat_message_metadata_passthrough": {"turn_id": "turn-a", "content_item_kinds": [kind]}}, minute)

def tokens(input_tokens, output_tokens, minute=2):
    usage = {"input_tokens": input_tokens, "cached_input_tokens": input_tokens // 2,
             "output_tokens": output_tokens, "reasoning_output_tokens": output_tokens // 2}
    return event("event_msg", {"type": "token_count", "info": {
        "total_token_usage": usage, "last_token_usage": usage}}, minute)

def write(name, rows):
    (root / (name + ".jsonl")).write_text("\n".join(json.dumps(row) for row in rows) + "\n")

call = event("response_item", {"type": "function_call", "name": "spawn_agent", "namespace": "collaboration",
    "call_id": "call-a", "arguments": '{"agent_type":"explorer"}'}, 3)
write("root", [meta("root-001"), event("event_msg", {"type": "task_started", "turn_id": "turn-a"}),
    message("instructions", "injected instructions", "agents_md.instructions"),
    message("user-a", "/grill a change"), message("user-a", "/grill a change"),
    event("event_msg", {"type": "user_message", "message": "/grill a change"}, 1),
    tokens(200000, 1000), call, call, tokens(800000, 4000, 4), tokens(800000, 4000, 4),
    event("event_msg", {"type": "token_count", "info": None}, 5),
    message("user-b", "response-only followup", minute=6),
    event("event_msg", {"type": "turn_aborted"}, 7)])
write("child", [meta("child-01", source={"subagent": {"thread_spawn": {"parent_thread_id": "root-001"}}}),
    message("child-task", "child task"), tokens(300000, 2500, 6)])
write("grandchild", [meta("grand-01", parent_thread_id="child-01", cwd="/work/elsewhere"), tokens(100000, 1500, 3)])
write("orphan", [meta("orphan01", parent_thread_id="missing-parent"), tokens(900000, 9000)])
write("guardian", [meta("guardian", source={"subagent": {"other": "guardian"}}), tokens(900000, 9000)])
# Forks repeat parent metadata and messages; the ordinal starts their own history.
inherited = [meta("root-001"), message("user-a", "inherited prompt"), tokens(9000000, 90000)]
write("fork", [meta("fork-001", forked_from_id="root-001", parent_thread_id="root-001",
    history_mode="paginated", subagent_history_start_ordinal=1 + len(inherited)), *inherited,
    message("fork-task", "fork task"), tokens(200000, 3000, 9)])
write("other", [meta("other-01", cwd="/work/other"), message("other-user", "other project")])
PYFIXTURE

out=$(CODEX_HOME="$codex_home" "$usage" --source codex --project demo --since 2026-09-25 --json --messages "$msgs")
assert_exit 0 "TC-6: Codex reads CODEX_HOME/sessions" || fail "TC-6"
assert_eq 1 "$(field count)" "TC-6: child, orphan and internal sessions are not human roots" || fail "TC-6: $out"
assert_eq root-001 "$(field sid)" "TC-6: identity uses the first metadata record" || fail "TC-6"
assert_eq 2 "$(field nuser)" "TC-6: user events and response messages count once, injected content excluded" || fail "TC-6"
assert_eq 4 "$(field out_k)" "TC-6: cumulative snapshots count once, reasoning is a subset" || fail "TC-6"
assert_eq 0.8 "$(field in_M)" "TC-6: cached input is a subset" || fail "TC-6"
assert_eq 1 "$(field interrupts)" "TC-6: turn aborts" || fail "TC-6"
assert_eq "{'grill': 1}" "$(field cmds)" "TC-6: commands in human messages" || fail "TC-6"
assert_eq "{'explorer': 1}" "$(field agents)" "TC-6: direct spawn calls deduplicated by call id" || fail "TC-6"
assert_eq 3 "$(field nsubs)" "TC-6: descendants follow parent metadata across projects" || fail "TC-6"
assert_eq 7 "$(field sub_out_k)" "TC-6: child snapshots exclude inherited fork counters" || fail "TC-6"
assert_eq 0.3 "$(field sub_h)" "TC-6: own child durations sum" || fail "TC-6"
printf '%s' "$out" | python3 -c '
import json, sys
assert json.load(sys.stdin) == [{"project": "/work/demo", "sid": "root-001", "title": None, "start": "2026-09-25 10:00", "wall_h": 0.1, "active_h": 0.1, "nuser": 2, "interrupts": 1, "skills": {}, "cmds": {"grill": 1}, "agents": {"explorer": 1}, "out_k": 4, "in_M": 0.8, "nsubs": 3, "sub_out_k": 7, "sub_h": 0.3}]
' || fail "usage#measurements-preserved: complete Codex record"
body=$(cat "$msgs")
assert_eq "=== /work/demo root-001 2026-09-25 10:01
/grill a change
=== /work/demo root-001 2026-09-25 10:06
response-only followup" "$body" "usage#measurements-preserved: exact Codex message export" || fail "$body"
assert_contains "$body" "response-only followup" "TC-6: response-only user messages are exported" || fail "TC-6"
for skipped in "injected instructions" "child task" "fork task" "inherited prompt"; do
  ! printf '%s' "$body" | grep -qF "$skipped" || fail "TC-6: '$skipped' should not be a human message"
done
out=$("$usage" --source codex --root "$codex_home/sessions" --project demo)
assert_contains "$out" "/work/demo	1	0.1	0.1	2	4	3	0.3" "TC-7: Codex table and explicit root" || fail "TC-7: $out"
out=$("$usage" --source codex --root "$codex_home/sessions" --since 2026-09-26 --json)
assert_eq '[]' "$out" "TC-7: Codex date filter" || fail "TC-7"

for selector in omitted unknown ../claude /tmp/claude 'claude/name'; do
  if [ "$selector" = omitted ]; then
    out=$("$usage" --root "$root" --json 2>&1)
  else
    out=$("$usage" --source "$selector" --root "$root" --json 2>&1)
  fi
  rc=$?
  assert_eq 2 "$rc" "usage#format-is-explicit: $selector source refuses" || fail "$out"
  assert_contains "$out" "source" "usage#format-is-explicit: actionable source error" || fail "$out"
done

portable=$(mktemp_dir)
mkdir -p "$portable/scripts" "$portable/adapters/fixture-format" "$portable/adapters/missing"
cp "$usage" "$repo_root/scripts/adapter.py" "$portable/scripts/"
cat > "$portable/adapters/fixture-format/usage.py" <<'PYREADER'
from pathlib import Path

def default_root():
    return str(Path(__file__).parent)

def sessions(root, project_filter=None):
    yield {"project": "fixture-project", "start": "2026-09-25 00:00"}, []
PYREADER
out=$("$portable/scripts/usage" --source fixture-format --json)
assert_exit 0 "usage#format-is-explicit: another adapter needs no catalogue edit" || fail "$out"
assert_contains "$out" "fixture-project" "usage#measurements-preserved: normalized reader records" || fail "$out"
ln -s "$repo_root/adapters/claude" "$portable/adapters/escape"
for selector in missing escape; do
  out=$("$portable/scripts/usage" --source "$selector" --root "$root" --json 2>&1)
  assert_exit 2 "usage#format-is-explicit: $selector capability refuses" || fail "$out"
done
assert_contains "$out" "outside adapters/" "usage#format-is-explicit: containment error" || fail "$out"
[ ! -d "$portable/scripts/__pycache__" ] && [ ! -d "$portable/adapters/fixture-format/__pycache__" ] \
  || fail "validation#portable-default: normal invocation leaves no bytecode artifacts"

exit 0
