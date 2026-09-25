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
{"type":"assistant","timestamp":"2026-09-25T10:05:00Z","message":{"id":"m1","role":"assistant","usage":{"output_tokens":2600,"input_tokens":1000,"cache_read_input_tokens":400000,"cache_creation_input_tokens":100000},"content":[{"type":"tool_use","name":"Skill","input":{"skill":"dev-skills:grill"}}]}}
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

out=$("$usage" --root "$root" --project demo --since 2026-09-25 --json)
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
assert_eq "{'dev-skills:grill': 1}" "$(field skills)" "TC-2: skills" || fail "TC-2"
assert_eq "{'Explore': 1, '?': 1}" "$(field agents)" "TC-2: Agent and Task dispatches" || fail "TC-2"
assert_eq 1 "$(field nsubs)" "TC-2: subagents counted by transcript, not by meta file" || fail "TC-2"
assert_eq 3 "$(field sub_out_k)" "TC-2: subagent output tokens once per message, at the streamed final count" || fail "TC-2"
assert_eq 0.6 "$(field sub_h)" "TC-2: subagent hours" || fail "TC-2"

msgs="$root/msgs.txt"
out=$("$usage" --root "$root" --messages "$msgs")
assert_exit 0 "TC-3: the table exits 0" || fail "TC-3"
assert_contains "$out" "project	sessions	wall_h	active_h	nuser	out_k	nsubs	sub_h" "TC-3: the header" || fail "TC-3: $out"
assert_contains "$out" "-Users-me-Documents-Projects-demo	3	1.3	0.8	8	3	1	0.6" "TC-3: the demo row sums exact values" || fail "TC-3: $out"
assert_contains "$out" "-Users-me-other	1	0.0	0.0	1	0	0	0.0" "TC-3: one row per project" || fail "TC-3: $out"
body=$(cat "$msgs")
assert_contains "$body" "hello" "TC-3: human messages are written" || fail "TC-3"
assert_contains "$body" "CMD /grill an idea" "TC-3: a slash command is written as a message" || fail "TC-3"
for skipped in "tool text" "meta text" "injected" "from a sidechain"; do
  ! printf '%s' "$body" | grep -qF "$skipped" || fail "TC-3: '$skipped' should not be a human message"
done
[ "$(printf '%s\n' "$body" | grep -n 'hello' | cut -d: -f1)" -lt "$(printf '%s\n' "$body" | grep -n 'second' | cut -d: -f1)" ] \
  || fail "TC-3: messages are in time order"

"$usage" --root "$root/missing" >/dev/null 2>&1
assert_exit 2 "TC-4: a missing root exits 2" || fail "TC-4"
"$usage" --root "$root" --since 2026-9-1 >/dev/null 2>&1
assert_exit 2 "TC-4b: a malformed --since exits 2" || fail "TC-4b"
"$usage" --root "$root" --messages "$root/no/such/dir/m.txt" >/dev/null 2>&1
assert_exit 2 "TC-4c: --messages into a missing directory exits 2" || fail "TC-4c"

pipe_err="$root/pipe.err"
"$usage" --root "$root" --json 2>"$pipe_err" | true
[ ! -s "$pipe_err" ] || fail "TC-5: a closed pipe prints nothing on stderr: $(cat "$pipe_err")"

exit 0
