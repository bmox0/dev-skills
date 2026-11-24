#!/usr/bin/env bash
# approve, the state file, the render, status and the plan commands of pipeline.py,
# in a throwaway repo.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "pipeline.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
. "$repo_root/test/cli/lifecycle.sh"
# edit FILE OLD NEW: replace one exact string
edit() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b, 1))' "$@"; }

repo=$(mktemp_dir)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git commit -q --allow-empty -m base

# build#workflow-progress: listing is a separate protocol from explicit entry
assert_eq '' "$(cli status)" "an unrelated checkout gets an empty text listing" || exit 1
assert_eq '[]' "$(cli status --json)" "the default JSON listing stays an array" || exit 1
out=$(cli workflow --json)
printf '%s\n' "$out" | python3 -c '
import json, sys
try:
    route = json.load(sys.stdin)
except ValueError:
    sys.exit("explicit entry should print a JSON workflow")
assert route.get("plan") is None and route.get("stage") == "grill", route
assert [s["id"] for s in route.get("stages", [])] == [
    "grill", "prototype", "plan", "build", "build-verification", "judge", "human-review", "finish"
], route
assert route.get("actions", [])[0]["owner"] == "user and planner", route
step = route["actions"][0]
assert step.get("kind") == "work" and step.get("role") == "planner" and "argv" not in step, step
' || fail "build#typed-workflow-actions: explicit entry describes planning work across the eight-stage route"
assert_contains "$(cli workflow)" "Grill (optional)" "build#workflow-progress: text entry names optional grill" || exit 1
assert_contains "$(cli workflow)" "Prototype (optional)" "build#workflow-progress: text entry names optional prototype" || exit 1
[ ! -e .ai-workflow ] || fail "build#workflow-progress: entry creates no workflow files"

mkdir -p .ai-workflow/plans .ai-workflow/epics docs/spec skills/tdd
touch skills/tdd/SKILL.md docs/spec/build.md
printf '# Epic\n\n## Plans\n\n| # | Plan | Waits for | Status |\n|---|---|---|---|\n| 1 | One | — | |\n| 2 | Two | 1 | |\n' > .ai-workflow/epics/e.md
epic_before=$(sed -n 1,7p .ai-workflow/epics/e.md)

plan=.ai-workflow/plans/2026-11-16-x.md
cat > "$plan" <<'P'
# Plan: x

Status: draft · branch `x` · base `<sha>`
Epic: `.ai-workflow/epics/e.md` · row 1
Prototype: none
Grill: done

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. One — `waiting`

Do.
Territory: `src/`, `a.txt`
Skills: `skills/tdd/SKILL.md`
Spec: none
Waits for: nothing

### 2. Two — `waiting`

Do.
Territory: `src/b/`
Skills: `skills/tdd/SKILL.md`, `skills/nope/SKILL.md`
Spec: `docs/spec/build.md`
Waits for: 9 — a thing

### 3. Three — `waiting`

Territory: `src/c`
Skills: none
Spec: none
Waits for: 1

## Checks

- Gate: normal — logic

## Done

1. a → b

## Spec

none
P

example="$repo_root/skills/run-file/references/example.run.toml"

typed_action() {
  local action_plan="$1" stage="$2" kind="$3" owner="$4" phrase="$5" expected="${6:-}" mode="${7:-inspect}"
  shift "$(( $# < 7 ? $# : 7 ))"
  local view status result
  view=$(cli status "$action_plan" --json "$@") || fail 'read typed status'
  status=$(cli status "$action_plan" "$@") || fail 'read text status'
  result=$(printf '%s\n' "$view" | python3 -c '
import json, os, subprocess, sys
stage, kind, owner, phrase, expected, mode = sys.argv[1:]
view = json.load(sys.stdin)["workflow"]
assert view["stage"] == stage, view
for action in view["actions"]:
    assert action.get("kind") in {"run", "work", "wait", "ask"}, action
    assert ("argv" in action) == (action["kind"] == "run"), action
    if action["kind"] == "work":
        assert action.get("role") and isinstance(action.get("assignment"), dict), action
    if action["kind"] == "run":
        argv = action["argv"]
        assert len(argv) >= 4 and os.path.isabs(argv[0]) and os.path.isabs(argv[1]), action
        assert view["plan"] in argv and all(isinstance(arg, str) for arg in argv), action
matching = [a for a in view["actions"] if a["kind"] == kind and a["owner"] == owner and phrase in a["action"]]
assert matching, view
action = matching[0]
for key, value in json.loads(expected or "{}").items():
    assert action.get(key) == value, action
if mode == "run":
    subprocess.run(action["argv"], cwd="/", check=True, stdout=subprocess.DEVNULL)
print(f"{owner} — " + action["action"])
' "$stage" "$kind" "$owner" "$phrase" "$expected" "$mode") || fail "build#typed-workflow-actions: $stage $kind $owner $phrase"
  assert_contains "$status" "$result" 'build#typed-workflow-actions: the text presents the same action' || exit 1
}

# build#state-through-commands: a broken plan gives one line per problem and no JSON
out=$(approve_plan "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses a broken plan" || exit 1
assert_eq 3 "$(printf '%s\n' "$out" | grep -c "^$plan:[0-9]*: ")" "one line per problem: $out" || exit 1
assert_contains "$out" "phase 2 waits for phase 9" "names the missing phase" || exit 1
assert_contains "$out" "skills/nope/SKILL.md does not exist" "names the missing skill" || exit 1
assert_contains "$out" "phases 1 and 2 both change" "names the unordered overlap" || exit 1
[ ! -e "${plan%.md}.json" ] || fail "no JSON after a refusal"

edit "$plan" 'Waits for: 9 — a thing' 'Waits for: 1 — a thing'
edit "$plan" ', `skills/nope/SKILL.md`' ''

# run#required-to-approve: a draft with no run file is refused, naming the skill, with no JSON
out=$(approve_plan "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses a plan with no run file" || exit 1
assert_contains "$out" "dev-skills:run-file" "the fix names the skill" || exit 1
[ ! -e "${plan%.md}.json" ] || fail "no JSON after a refusal"

cp "$example" "${plan%.md}.run.toml"
draft=$(cat "$plan")

# build#workflow-progress: a draft can be inspected before compilation or consent
out=$(cli status "$plan" --json)
printf '%s\n' "$out" | python3 -c '
import json, os, sys
try:
    status = json.load(sys.stdin)
except ValueError:
    sys.exit("status should describe the named draft before compilation")
view = status.get("workflow", {})
assert status.get("status") == "draft" and view.get("stage") == "plan", status
assert view.get("plan") == os.path.abspath(sys.argv[1]), view
assert [(s["id"], s["state"]) for s in view["stages"][:2]] == [("grill", "done"), ("prototype", "skipped")], view
assert "approve" in view["actions"][0]["action"], view
' "$plan" || fail "build#workflow-progress: the draft shows recorded optional history"
[ ! -e "${plan%.md}.json" ] || fail "build#workflow-progress: inspection compiles nothing"
typed_action "$plan" plan run Planner 'Validate the draft' '{}' run
assert_contains "$(cli status "$plan")" 'run approve' "build#workflow-progress: the validated draft awaits run approval" || exit 1
typed_action "$plan" plan ask 'User and planner' 'run approve'
cli run approve "$plan" --by user --words 'Fixture run approved' >/dev/null || fail "approve run"
assert_contains "$(cli status "$plan")" 'summary approve' "build#workflow-progress: a run approval leaves the summary pending" || exit 1
typed_action "$plan" plan ask 'User and planner' 'summary approve'
[ "$(git branch --show-current)" != x ] || fail "build#workflow-progress: run consent does not start the build"

out=$(approve_plan "$plan"); rc=$?
assert_eq 0 "$rc" "approve passes: $out" || exit 1
last=$(printf '%s\n' "$out" | tail -1)
[[ "$last" =~ ^"1 → 2 ∥ 3 · normal · "[0-9]+" words"$ ]] || fail "the last line: $last"
[ -f "${plan%.md}.json" ] || fail "the JSON exists"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${plan%.md}.json" || fail "the JSON parses"
changed=$(diff <(printf '%s\n' "$draft") "$plan" | grep '^[<>]' | cut -c1-17)
assert_eq "$(printf '< Status: draft ·\n> Status: approve\n> Rendered from `')" "$changed" "the render touches only Status and its line: $changed" || exit 1
assert_eq "approved · \`.ai-workflow/plans/2026-11-16-x.md\`" "$(sed -n 7p .ai-workflow/epics/e.md | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')" "the epic row follows approve" || exit 1
assert_eq "$(sed -n 1,6p .ai-workflow/epics/e.md)" "$(printf '%s\n' "$epic_before" | sed -n 1,6p)" "the epic is otherwise untouched" || exit 1
assert_eq "| 2 | Two | 1 | |" "$(sed -n 8p .ai-workflow/epics/e.md)" "the other row is untouched" || exit 1
assert_contains "$(cli status "$plan")" 'separate start instruction' "build#workflow-progress: summary approval awaits a start instruction" || exit 1
typed_action "$plan" plan wait Coordinator 'separate start instruction'
[ "$(git branch --show-current)" != x ] || fail "build#workflow-progress: summary consent does not start the build"

# build#state-through-commands: status, base and the epic row
cli build start "$plan" --base HEAD --note "start" >/dev/null || fail "plan status"
cli plan base "$plan" HEAD >/dev/null || fail "plan base"
sha=$(git rev-parse HEAD)
grep -q "^Status: building · branch \`x\` · base \`$sha\`$" "$plan" || fail "the Status line follows the commands"
assert_contains "$(sed -n 7p .ai-workflow/epics/e.md)" "building ·" "the epic row follows" || exit 1
out=$(cli status "$plan")
assert_contains "$out" "Ready: 1" "phase 1 is ready" || exit 1
assert_contains "$out" "start" "the note shows" || exit 1
assert_contains "$out" 'phase start' "build#workflow-progress: the coordinator can open a ready phase" || exit 1
cli phase start "$plan" 1 >/dev/null || fail "start Phase 1"
out=$(cli status "$plan")
assert_contains "$out" 'Implementer for phase 1' "build#workflow-progress: a running phase has an owner" || exit 1
assert_contains "$out" 'Phase 2 waits for phase 1' "build#workflow-progress: a dependent phase names its blocker" || exit 1
out=$(cli plan status "$plan" nonsense); rc=$?
assert_eq 1 "$rc" "a value outside the list is refused" || exit 1
assert_contains "$out" "bad-status:" "code form" || exit 1
assert_contains "$out" "— fix:" "fix form" || exit 1

# build#state-through-commands: a hand edit of a code-owned line: writes refuse naming the command, status still prints
edit "$plan" 'Status: building' 'Status: passed'
out=$(cli plan status "$plan" merged); rc=$?
assert_eq 1 "$rc" "a write refuses on drift" || exit 1
assert_contains "$out" "drift:" "drift code" || exit 1
assert_contains "$out" "pipeline.py plan status" "names the command" || exit 1
out=$(cli status "$plan"); rc=$?
assert_eq 0 "$rc" "status prints on drift" || exit 1
assert_contains "$out" "Drift:" "status shows the drift" || exit 1
out=$(approve_plan "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses an edited code-owned line" || exit 1
assert_contains "$out" "pipeline.py plan status" "approve names the command" || exit 1
edit "$plan" 'Status: passed' 'Status: building'

# build#state-through-commands: a text edit: writes refuse, approve recompiles and keeps the statuses
edit "$plan" '1. a → b' '1. a → b
2. c → d'
out=$(cli plan status "$plan" passed); rc=$?
assert_eq 1 "$rc" "a write refuses after a text edit" || exit 1
assert_contains "$out" "pipeline.py approve" "names approve" || exit 1
approve_plan "$plan" >/dev/null || fail "approve recompiles"
grep -q '^Status: building · ' "$plan" || fail "the status is kept"
cli plan status "$plan" passed >/dev/null && fail "compilation cannot replace acceptance"
cli plan status "$plan" building >/dev/null || fail "approved progress remains writable"

# the lock: parallel writers all land
for i in 1 2 3 4 5 6; do git commit -q --allow-empty -m "c$i"; git tag "t$i"; done
for i in 1 2 3 4 5 6; do cli plan base "$plan" "t$i" --note "w$i" >/dev/null & done
wait
python3 - "${plan%.md}.json" <<'PY' || fail "every parallel write is recorded"
import json, sys
notes = [e["note"] for e in json.load(open(sys.argv[1]))["history"] if e["note"] and e["note"].startswith("w")]
assert sorted(notes) == ["w1", "w2", "w3", "w4", "w5", "w6"], notes
PY
grep -q '^Status: building' "$plan" || fail "the plan is still rendered"

# a started phase may not vanish
python3 -B - "$pipeline" "$plan" <<'PY'
import sys; sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
import pipeline
plan = sys.argv[2]
with pipeline.writing(plan) as st:
    pipeline.set_phase(plan, st, 1, "done", "test")
    print("ready", pipeline.ready_phases(st))
PY
grep -q '^### 1. One — `done`$' "$plan" || fail "set_phase renders the heading"
cp "$plan" "$plan.bak"
python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); i=s.index("### 1."); j=s.index("### 2."); open(p,"w").write(s[:i]+s[j:])' "$plan"
edit "$plan" '### 2. Two' '### 1. Two'
edit "$plan" '### 3. Three' '### 2. Three'
edit "$plan" 'Waits for: 1 — a thing' 'Waits for: nothing'
out=$(approve_plan "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses a renumbered started phase" || exit 1
assert_contains "$out" "phase-gone:" "refused as gone: $out" || exit 1
case "$out" in *"edited by hand"*) fail "not a hand-edit refusal: $out";; esac
cp "$plan.bak" "$plan"; rm "$plan.bak"
for n in 2 3; do cli phase start "$plan" "$n" >/dev/null || fail "start phase $n"; done
out=$(cli status "$plan")
assert_contains "$out" 'Implementer for phase 2' "build#workflow-progress: phase 2 runs independently" || exit 1
assert_contains "$out" 'Implementer for phase 3' "build#workflow-progress: phase 3 has its own parallel owner" || exit 1
typed_action "$plan" build work 'Implementer for phase 2' 'Work from the phase brief' '{"role":"implementer","assignment":{"phase":2,"kind":"phase"}}'
typed_action "$plan" build work 'Implementer for phase 3' 'Work from the phase brief' '{"role":"implementer","assignment":{"phase":3,"kind":"phase"}}'

# build#pre-5-1-adopted: a plan with no state is adopted as its file stands
old=.ai-workflow/plans/2026-11-10-old.md
cat > "$old" <<'P'
# Plan: old

Status: building · branch `old` · base `abc1234`

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. First — `done`

Territory: `src/`
Skills: none
Spec: none
Waits for: nothing

### 2. Second — `in progress`

Territory: `lib/`
Skills: none
Spec: none
Waits for: 1

### 3. Third — `waiting`

Territory: `src/`
Skills: none
Spec: none
Waits for: 1, 2

## Checks

- Gate: small — looks

## Done

1. a → b

## Spec

none
P
out=$(cli plan status "$old" passed); rc=$?
assert_eq 1 "$rc" "a plan with no state is refused" || exit 1
assert_contains "$out" "pipeline.py approve" "the fix names approve" || exit 1
out=$(approve_plan "$old"); rc=$?
assert_eq 0 "$rc" "approve adopts: $out" || exit 1
assert_contains "$out" "overlaps 2026-11-16-x (building): src/" "names the overlapping plan" || exit 1
grep -q '^### 1. First — `done`$' "$old" || fail "phase 1 stays done"
grep -q '^Status: building · branch `old` · base `abc1234`$' "$old" || fail "status is kept"
out=$(cli status "$old")
assert_contains "$out" "Ready: none" "phase 3 waits for phase 2" || exit 1
assert_contains "$out" 'Grill (optional) — unknown' "build#workflow-progress: a legacy plan has unknown grill history" || exit 1
assert_contains "$out" 'Prototype (optional) — unknown' "build#workflow-progress: a legacy plan has unknown prototype history" || exit 1
case "$out" in *None*) fail "an unset previous value prints as a dash: $out";; esac
assert_contains "$out" "phase 2 — → in progress" "an unset previous value prints as a dash" || exit 1
cli status | grep -q "2026-11-10-old — building" || fail "status of all plans"

# the Human gate part of the file is not touched
printf '\n## Human gate\n\nwritten by hand\n' >> "$old"
out=$(cli plan status "$old" "at the human gate"); rc=$?
assert_eq 1 "$rc" "legacy adoption does not infer approval" || exit 1
assert_contains "$out" "run-unapproved" "a handwritten gate supplies no approval" || exit 1
tail -2 "$old" | grep -q 'written by hand' || fail "the gate stays as written"

# status lists plans only: no briefs or gate logs, and no approve fix for a merged plan without state
plans=.ai-workflow/plans
printf 'x\n' > "$plans/2026-11-16-x.brief-judge.md"
printf 'x\n' > "$plans/2026-11-16-x.brief-implementer-1.md"
printf 'x\n' > "$plans/2026-11-10-old.gate-log.md"
printf '# Plan: m\n\nStatus: merged · branch `m` · base `abc1234`\n' > "$plans/2026-11-01-m.md"
out=$(cli status)
case "$out" in *brief*|*gate-log*) fail "status lists only plans: $out";; esac
case "$out" in *2026-11-01-m*) fail "status leaves out a merged plan: $out";; esac
printf '# Plan: nb\n\nStatus: building · branch `nb` · base `abc1234`\n' > "$plans/2026-11-02-nb.md"
printf '# Plan: dr\n\nStatus: draft · branch `dr` · base `<sha>`\n' > "$plans/2026-11-03-dr.md"
out=$(cli status)
assert_contains "$out" "2026-11-02-nb — no state — fix: run \`pipeline.py approve\`" "a building plan without state shows with its fix" || exit 1
case "$out" in *2026-11-03-dr*) fail "status leaves out a draft plan: $out";; esac
cli status --json | python3 -c '
import json, sys
rows = json.load(sys.stdin)
assert all(set(r) == {"plan", "status", "ready", "drift", "stale"} for r in rows), rows
names = {r["plan"] for r in rows}
assert {"2026-11-01-m", "2026-11-03-dr"}.isdisjoint(names), names
' || fail "--json keeps the existing listing protocol"

# a small valid plan: mkp FILE BRANCH EPIC-LINE [APPROACH-EXTRA]
mkp() {
  set -- "$1" "$2" "${3:-}" "${4:-}" "${5:-}"
  cat > "$1" <<P
# Plan: $2

Status: draft · branch \`$2\` · base \`<sha>\`
$3

## Result

R.

## Approach

A.
$4

## Out of scope

- n

## Phases

### 1. One — \`waiting\`

Do one.
$5
Territory: \`src/\`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — x

## Done

1. a → b

## Spec

none
P
  cp "$example" "${1%.md}.run.toml"
}

# status without a plan lists building to passed; a named plan always shows
mkp "$plans/2026-11-04-ap.md" ap ''
approve_plan "$plans/2026-11-04-ap.md" >/dev/null || fail "approve ap"
case "$(cli status)" in *2026-11-04-ap*) fail "status leaves out an approved plan";; esac
assert_contains "$(cli status "$plans/2026-11-04-ap.md")" "approved" "a named plan shows" || exit 1
assert_contains "$(cli status --help)" "building" "--help says which plans" || exit 1

# build#epic-row-follows: the row sits in the Plans table, keeps its cell format, and parallel plans of one epic both land
cat > .ai-workflow/epics/e2.md <<'E'
# Epic

| # | Note |
|---|---|
| 1 | not the plans table |

## Plans

| # | Plan | Waits for | Status |
|---|---|---|---|
| 1 | One | — | |
| 2 | Two | 1 | building · `.ai-workflow/plans/old.md` |
| 3 | Three | 2 | |
E
e2=.ai-workflow/epics/e2.md
mkp "$plans/2026-11-05-p1.md" p1 'Epic: `.ai-workflow/epics/e2.md` · row 1'
mkp "$plans/2026-11-05-p2.md" p2 'Epic: `.ai-workflow/epics/e2.md` · row 2'
approve_plan "$plans/2026-11-05-p1.md" >/dev/null || fail "approve p1"
approve_plan "$plans/2026-11-05-p2.md" >/dev/null || fail "approve p2"
assert_contains "$(cat $e2)" '| 1 | not the plans table |' "a row outside the Plans table is untouched" || exit 1
assert_contains "$(cat $e2)" '| 1 | One | — | approved · `.ai-workflow/plans/2026-11-05-p1.md` |' "an empty cell gets the epic's shape" || exit 1
assert_contains "$(cat $e2)" '| 2 | Two | 1 | approved · `.ai-workflow/plans/2026-11-05-p2.md` |' "a filled cell keeps its shape" || exit 1
cli build start "$plans/2026-11-05-p1.md" --base HEAD >/dev/null || fail "build p1"
cli build start "$plans/2026-11-05-p2.md" --base HEAD >/dev/null || fail "build p2"
for s in building approved building approved building; do
  cli plan status "$plans/2026-11-05-p1.md" "$s" >/dev/null &
  cli plan status "$plans/2026-11-05-p2.md" "$s" >/dev/null &
  wait
  assert_contains "$(cat $e2)" "| 1 | One | — | $s · " "row 1 holds $s" || exit 1
  assert_contains "$(cat $e2)" "| 2 | Two | 1 | $s · " "row 2 holds $s" || exit 1
done

# the row names the plan relative to the tree, also through a symlinked path
link=$(mktemp_dir)/link
ln -s "$(pwd -P)" "$link"
mkp "$plans/2026-11-05-p3.md" p3 'Epic: `.ai-workflow/epics/e2.md` · row 3'
approve_plan "$link/.ai-workflow/plans/2026-11-05-p3.md" >/dev/null || fail "approve p3 through a link"
assert_contains "$(cat $e2)" '| 3 | Three | 2 | approved · `.ai-workflow/plans/2026-11-05-p3.md` |' "the row path is relative through a symlink" || exit 1

# fenced blocks are text: a heading or Status line in one is neither parsed nor rewritten
fence='
```text
### 2. Fake — `waiting`
Territory: `nowhere/`
### 1. One — `waiting`
```'
pf="$plans/2026-11-06-pf.md"
mkp "$pf" pf '' "$fence" "$fence"
out=$(approve_plan "$pf"); rc=$?
assert_eq 0 "$rc" "approve ignores a fenced phase heading: $out" || exit 1
python3 -B - "$pipeline" "$pf" <<'PY' || fail "set_phase"
import sys; sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
import pipeline
with pipeline.writing(sys.argv[2]) as st:
    pipeline.set_phase(sys.argv[2], st, 1, "done", "test")
PY
assert_eq 2 "$(grep -c '^### 1. One — `waiting`$' "$pf")" "the fenced heading copies keep their text" || exit 1
edit "$pf" 'Do one.' 'Do one, again.'
out=$(cli plan status "$pf" passed); rc=$?
assert_eq 1 "$rc" "a text edit refuses the write" || exit 1
case "$out" in *"edited by hand"*) fail "a fenced heading is not a hand edit: $out";; esac
assert_contains "$out" "pipeline.py approve" "the fix is approve" || exit 1

# run#starts-from-last: run new copies the newest run file, else the example, and never overwrites
r=$(mktemp_dir)
cd "$r" && git init -q && cp "$repo_root/AGENTS.md" AGENTS.md && mkdir -p .ai-workflow/plans && cd .ai-workflow/plans || exit 1
out=$(cli run new 2026-11-20-a.md); rc=$?
assert_eq 0 "$rc" "run new: $out" || exit 1
assert_contains "$out" "2026-11-20-a.run.toml" "run new names the file" || exit 1
assert_contains "$out" "copied from" "run new names the source" || exit 1
[ -z "$(cli run check 2026-11-20-a.md)" ] || fail "the example passes run check"
python3 - 2026-11-20-a.run.toml "$example" <<'P' || fail "a first run file is the example with an empty [run]"
import sys, tomllib
a, b = (tomllib.load(open(f, "rb")) for f in sys.argv[1:])
assert a.pop("executors") and a.pop("run") == {} and b.pop("run") and a == b
P
printf 'quota = 33\n' >> 2026-11-20-a.run.toml
touch -t 202611210000 2026-11-20-a.run.toml
cp "$example" 2026-11-19-old.run.toml; touch -t 202611200000 2026-11-19-old.run.toml
cli run new 2026-11-22-b.md >/dev/null || fail "run new b"
grep -q 'quota = 33' 2026-11-22-b.run.toml || fail "run new copies the newest"
cp 2026-11-22-b.run.toml before.toml
out=$(cli run new 2026-11-22-b.md); rc=$?
assert_eq 1 "$rc" "run new refuses to overwrite" || exit 1
assert_contains "$out" "run-exists:" "code form" || exit 1
cmp -s before.toml 2026-11-22-b.run.toml || fail "the file is unchanged"
rm before.toml

# run#contract-checked: one line per problem, naming its section and key; [run] takes plain values
cat > 2026-11-23-c.run.toml <<'T'
[finish]
mode = "x"
how = "squash"
target = "main"
delete_backups = true
[checks]
phase = []
dev = "serve {port}"
[isolation]
worktree = false
port = false
data_dir = false
[deploy]
x = 1
[run]
t = { a = 1 }
l = [1]
admin_pwd = "keychain:app/admin"
can_remove_tasks = false
quota = 20
T
out=$(cli run check 2026-11-23-c.md); rc=$?
assert_eq 1 "$rc" "run check refuses" || exit 1
assert_eq 7 "$(printf '%s\n' "$out" | grep -c ' — fix: ')" "one line per problem: $out" || exit 1
for want in 'run-unknown-key: [finish] mode' 'run-bad-value: [finish] how' 'run-missing-key: [checks] full' 'run-unknown-section: [deploy]' 'run-bad-type: [run] t ' 'run-bad-type: [run] l ' 'run-bad-placeholder: [checks] dev uses {port}'; do
  assert_contains "$out" "$want" "names $want" || exit 1
done
case "$out" in *admin_pwd*|*can_remove*|*quota*) fail "plain [run] values pass: $out";; esac
cd "$repo" || exit 1

# run#changes-through-approve: recorded at approve; a changed file is drift, the approved value stands, approve takes it
pr="$plans/2026-11-24-r.md"
mkp "$pr" r ''
approve_plan "$pr" >/dev/null || fail "approve r"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["run"]["finish"]["delete_backups"] is True' "${pr%.md}.json" || fail "the state records the run file"
edit "${pr%.md}.run.toml" 'delete_backups = true' 'delete_backups = false'
out=$(cli status "$pr")
assert_contains "$out" "Drift: " "status reports the drift" || exit 1
assert_contains "$out" "[finish] delete_backups" "status names the key" || exit 1
out=$(cli run show "$pr")
assert_contains "$out" 'delete_backups = true' "run show gives the approved value" || exit 1
assert_contains "$out" "Drift: " "run show reports the drift" || exit 1
assert_eq true "$(cli run show --json "$pr" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["run"]["finish"]["delete_backups"]))')" "--json gives the approved value" || exit 1
approve_plan "$pr" >/dev/null || fail "approve r again"
assert_contains "$(cli run show "$pr")" 'delete_backups = false' "approve takes the new value" || exit 1
case "$(cli status "$pr")" in *Drift:*) fail "no drift after approve";; esac
# a changed value is a history entry naming section and key, and 1 -> true is a change
out=$(cli status "$pr")
assert_contains "$out" "finish delete_backups" "status lists the changed key in the history" || exit 1
cat >> "${pr%.md}.run.toml" <<'T'
T
python3 - "${pr%.md}.run.toml" <<'P'
import sys, re
p = sys.argv[1]; t = open(p).read()
t = re.sub(r"(?ms)^\[run\].*\Z", "", t) + "[run]\nquota = 1\n"
open(p, "w").write(t)
P
approve_plan "$pr" >/dev/null || fail "approve quota"
edit "${pr%.md}.run.toml" 'quota = 1' 'quota = true'
assert_contains "$(cli status "$pr")" "[run] quota" "1 -> true is drift" || exit 1
approve_plan "$pr" >/dev/null || fail "approve quota true"
assert_contains "$(cli status "$pr")" "run quota" "the history names run quota" || exit 1
# a bad file is refused by approve with run check's lines
edit "${pr%.md}.run.toml" 'how = "merge-request"' 'how = "squash"'
out=$(approve_plan "$pr"); rc=$?
assert_eq 1 "$rc" "approve refuses a bad run file" || exit 1
assert_contains "$out" "run-bad-value: [finish] how" "run check's line" || exit 1

# run#required-to-approve: a pre-5.1 plan at building with no run file is adopted
po="$plans/2026-11-02-pre.md"
mkp "$po" pre ''
rm "${po%.md}.run.toml"
sed -i.bak 's/^Status: draft/Status: building/' "$po"; rm "$po.bak"
approve_plan "$po" >/dev/null || fail "adopt a plan without a run file"
python3 -c 'import json,sys; assert "run" not in json.load(open(sys.argv[1]))' "${po%.md}.json" || fail "no run recorded"

# build#workflow-progress: the same view follows gate, judge, land, review and finish
route_repo="$(mktemp_dir)/repository with spaces"
mkdir -p "$route_repo" && cd "$route_repo" || exit 1
git init -q -b main
mkdir -p "$plans" src
echo base > src/a
git add src && git commit -q -m base || fail "commit fixture base"
route="$plans/2026-11-25-route.md"
mkp "$route" route $'Grill: skipped\nPrototype: `prototype.html`'
edit "$route" 'Gate: small' 'Gate: normal'
edit "$route" $'1. a → b\n\n## Spec' $'1. a → b\n2. c → d\n3. e → f\n\n## Spec'
edit "${route%.md}.run.toml" 'full = ["scripts/check", "scripts/test"]' 'full = []'
approve_plan "$route" >/dev/null || fail "approve route"
assert_contains "$(cli status "$route")" 'Grill (optional) — skipped' "build#workflow-progress: the plan can record a skipped grill" || exit 1
assert_contains "$(cli status "$route")" 'Prototype (optional) — done' "build#workflow-progress: the prototype field records a choice" || exit 1
cli build start "$route" --base main >/dev/null || fail "start route"
typed_action "$route" build run Coordinator 'Start phase 1' '{}' run
brief=$(cli brief implementer "$route" 1) || fail "brief route"
[[ -f "$brief" && "$brief" != *$'\n'* ]] || fail "build#workflow-progress: brief stdout is its one path"
echo route > src/a
git commit -q -m route -- src/a || fail "commit route"
cli phase report "$route" 1 --became route --commit "$(git rev-parse HEAD)" >/dev/null || fail "report route phase"
out=$(cli phase done "$route" 1); rc=$?
assert_eq 1 "$rc" "build#phase-check-outcomes: a configured check with only the legacy report field holds the phase" || exit 1
assert_contains "$out" 'scripts/check' "build#phase-check-outcomes: the refusal names the unchecked command" || exit 1
assert_contains "$(cli status "$route")" 'Implementer for phase 1 — Record the outcomes for scripts/check' "build#phase-check-outcomes: the implementer owns the missing report" || exit 1
assert_contains "$(cat "$brief")" 'Red before green' "build#phase-check-outcomes: the brief gives the TDD requirement" || exit 1
assert_contains "$(cat "$brief")" '--check' "build#phase-check-outcomes: the brief gives the reporting flag" || exit 1
out=$(cli phase report "$route" 1 --became route --check scripts/check 'failed: ' --commit "$(git rev-parse HEAD)"); rc=$?
assert_eq 1 "$rc" "build#phase-check-outcomes: a failure needs a reason" || exit 1
assert_contains "$out" 'bad-phase-outcome' "build#phase-check-outcomes: the refusal identifies the empty outcome" || exit 1
cli phase report "$route" 1 --became route --check scripts/check 'failed: missing fixture runner outside the phase territory' --commit "$(git rev-parse HEAD)" >/dev/null || fail "report route check"
out=$(cli phase done "$route" 1) || fail "close route phase"
assert_contains "$out" 'Coordinator — Open build verification with `gate start <plan>`' "build#workflow-progress: closing the last phase names gate start and its owner" || exit 1

route_step() {
  cli status "$route" --json | python3 -c '
import json, sys
stage, owner, text = sys.argv[1:]
status = json.load(sys.stdin)
view = status.get("workflow", {})
assert view.get("stage") == stage, view
assert any(a["owner"] == owner and text in a["action"] for a in view["actions"]), view
' "$@" || fail "build#workflow-progress: $1 should show $2 and $3"
}
route_step build-verification Coordinator 'gate start'
typed_action "$route" build-verification run Coordinator 'Open build verification' '{}' run
route_step build-verification Reviewer 'brief reviewer'
route_step build-verification Verify 'Done 1'
first_range="$(git rev-parse main)..$(git rev-parse HEAD)"
typed_action "$route" build-verification work Reviewer 'brief reviewer' "{\"role\":\"reviewer\",\"assignment\":{\"kind\":\"review\",\"cycle\":\"gate\",\"id\":\"gate\",\"range\":\"$first_range\"}}"
typed_action "$route" build-verification work Verify 'Done 1' "{\"role\":\"verify\",\"assignment\":{\"kind\":\"verify\",\"cycle\":\"gate\",\"id\":\"gate\",\"head\":\"$(git rev-parse HEAD)\",\"cases\":[1,2,3]}}"
assert_eq "[$(cli status "$route" --json)]" "$(cli status --current --json)" 'build#typed-workflow-actions: current JSON exposes the same route' || exit 1
out=$(cli brief judge "$route" --note 'Fixture permits missing E2E'); rc=$?
assert_eq 1 "$rc" "build#review-completion: E2E exceptions do not complete review" || exit 1
assert_contains "$out" 'review-missing' "build#review-completion: the refusal names the missing review" || exit 1
cli review complete "$route" --assignment gate --range "$first_range" >/dev/null || fail "complete clean review"
assert_contains "$(cli status "$route")" 'Review complete (0 findings in cycle)' "build#review-completion: clean review is visible even while E2E is pending" || exit 1
before=$(cli status "$route" --json)
cli review complete "$route" --assignment gate --range "$first_range" >/dev/null || fail "retry clean review"
assert_eq "$before" "$(cli status "$route" --json)" "build#review-completion: retry preserves completion evidence" || exit 1
cli result "$route" --case 1 --outcome passed --capture 'old fixture output' >/dev/null || fail "record old result"
old_head=$(git rev-parse HEAD)
echo changed >> src/a
git commit -q -m 'Change the examined tree' -- src/a || fail "change route after verification"
cli gate start "$route" >/dev/null || fail "refresh checks at changed head"
out=$(cli review complete "$route" --assignment gate --range "$first_range"); rc=$?
assert_eq 1 "$rc" "build#review-completion: an old range cannot complete a new review" || exit 1
route_step build-verification Reviewer 'stale'
route_step build-verification Verify 'Done 1'
out=$(cli result "$route" --case 1 --cycle gate --head "$old_head" --outcome passed --capture 'late old fixture output'); rc=$?
assert_eq 1 "$rc" "build#review-completion: a Verify worker cannot record a result from a stale brief" || exit 1
assert_contains "$out" 'result-target' "build#review-completion: the refusal names the stale tree" || exit 1
complete_review "$route" || fail "renew route review"
out=$(cli verdict pass "$route" --report 'Evidence from old tree' --predicted pass --engine fixture); rc=$?
assert_eq 1 "$rc" "build#review-completion: old E2E evidence cannot satisfy the verdict" || exit 1
assert_contains "$out" 'result-missing' "build#review-completion: the refusal identifies missing current results" || exit 1
cli verdict evidence-owed "$route" --owed verify --report 'Drive Done 1' >/dev/null || fail "record owed evidence"
route_step build-verification Verify 'Drive Done 1'
cli result "$route" --case 2 --outcome passed --capture 'current fixture output' >/dev/null || fail "record second case"
cli result "$route" --case 3 --outcome passed --capture 'current fixture output' >/dev/null || fail "record third case"
cli result "$route" --case 1 --outcome failed --detail 'Needs a fix' --capture 'fixture output' >/dev/null || fail "record route issue"
route_step build-verification Coordinator 'fix start'
cli fix start "$route" >/dev/null || fail "open fix"
route_step build-verification 'Fix implementer' 'fix report'
echo fixed >> src/a
git commit -q -m 'Fix the examined tree' -- src/a || fail "commit route fix"
cli fix report "$route" --became checked --commit "$(git rev-parse HEAD)" >/dev/null || fail "report route fix"
route_step build-verification Coordinator 'fix done'
cli fix done "$route" >/dev/null || fail "close route fix"
route_step build-verification Reviewer 'brief reviewer'
route_step build-verification Verify 'Done 1'
targeted=$(cli brief verify "$route" --cases 2) || fail "assign touched second case"
assert_contains "$(cat "$targeted")" '2. c → d' "build#review-completion: explicitly targeted case is in the Verify brief" || exit 1
route_step build-verification Verify 'Done 1, Done 2'
if grep -q '^3\. ' "$targeted"; then fail "build#review-completion: the unrelated case stays outside the targeted recheck"; fi
complete_review "$route" || fail "complete targeted route review"
cli result "$route" --case 1 --outcome passed --capture 'fixture output' >/dev/null || fail "record route verification"
out=$(cli brief judge "$route"); rc=$?
assert_eq 1 "$rc" "build#review-completion: an assigned recheck still needs its own result" || exit 1
assert_contains "$out" 'Done 2 lacks current E2E evidence' "build#review-completion: only the selected unfinished case is owed" || exit 1
cli brief judge "$route" --note 'Fixture cannot drive Done 2 yet' >/dev/null || fail "brief with an explicit E2E exception"
cli verdict question "$route" --report 'Needs input' --question 'Keep the title?' --predicted pass --engine fixture --evidence-note 'Fixture cannot drive Done 2 yet' >/dev/null || fail "record route question"
assert_contains "$(cli status "$route")" 'evidence exception: Fixture cannot drive Done 2 yet' "build#review-completion: status preserves the judge's reason for missing E2E evidence" || exit 1
route_step judge User 'Keep the title?'
typed_action "$route" judge ask User 'Keep the title?'
cli result "$route" --case 2 --outcome passed --capture 'resolved fixture output' >/dev/null || fail "complete targeted second case"
cli brief judge "$route" --note 'Keep the current title' >/dev/null || fail "relay the user's answer"
typed_action "$route" judge run Coordinator 'brief judge' '{}' run
cli verdict pass "$route" --report 'Question answered' >/dev/null || fail "pass route"
route_step judge Judge 'land draft'
typed_action "$route" judge run Judge 'land draft' '{}' run
typed_action "$route" judge work Judge 'message and a walkthrough'
edit "${route%.md}.shape.toml" 'message = ""' 'message = "feat: route"'
edit "${route%.md}.shape.toml" 'walkthrough = ""' 'walkthrough = "See src/a"'
typed_action "$route" judge run Judge 'Use the current commit shape' '{}' run
route_step judge Coordinator 'page'
typed_action "$route" judge work Coordinator 'page'
route_guide=$'\n\n#### Checks\n\n- —\n\n#### Decisions\n\n- —'
cli page "$route" --guide "Read src/a$route_guide" --message 'feat: route' >/dev/null || fail "render route page"
route_step human-review user 'accept'
typed_action "$route" human-review ask user 'accept'
cli note add "$route" --text 'Change the line' --cause bug >/dev/null || fail "add route note"
route_step human-review User 'authorize a round'
cli round start "$route" >/dev/null || fail "open route round"
route_step build 'Round implementer' 'round report'
echo revised > src/a
git commit -q -m revise -- src/a || fail "commit route round"
cli round report "$route" --became revised --commit "$(git rev-parse HEAD)" >/dev/null || fail "report route round"
typed_action "$route" build work Coordinator 'Record the note sources'
cli note edit "$route" 1 --source missed >/dev/null || fail "record note source"
typed_action "$route" build run Coordinator 'round done' '{}' run
route_step build-verification Reviewer 'brief reviewer'
git commit -q --allow-empty -m 'Same checked tree' || fail "commit on checked round tree"
route_step build-verification Reviewer 'brief reviewer'
echo drift >> src/a
git commit -q -m 'Changed checked tree' -- src/a || fail "move fixture beyond checked round"
route_step build-verification Coordinator 'Restore the checked round tree'
git reset -q --hard HEAD^ || fail "restore the fixture's checked tree"
complete_review "$route" || fail "complete round review"
cli verdict pass "$route" --report 'Revised' >/dev/null || fail "pass route round"
route_step judge Judge 'land draft'
cli land draft "$route" >/dev/null || fail "draft new route shape"
edit "${route%.md}.shape.toml" 'since = ""' 'since = "Revised the line"'
cli land "$route" >/dev/null || fail "land route round"
cli page "$route" --guide "Read the revised src/a$route_guide" --message 'feat: route' >/dev/null || fail "render revised route page"
route_step human-review user 'accept'
cli accept "$route" --by user --words 'Looks good' >/dev/null || fail "accept route"
route_step finish Coordinator 'finish'
typed_action "$route" finish work Coordinator 'Configure the request'
git remote add origin https://example.invalid/route.git || fail "configure fixture remote"
typed_action "$route" finish run Coordinator 'approved ending' '{}' run
route_step finish Coordinator 'plan status'
request=https://example.invalid/route/requests/1
cli plan status "$route" "$request" >/dev/null || fail "record fixture request"
route_step finish Coordinator "$request"
typed_action "$route" finish wait Coordinator "$request"
assert_contains "$(cli status --current)" "Wait for $request to merge" "build#workflow-progress: resume shows the outstanding merge" || exit 1
cli finish --merged "$route" >/dev/null || fail "record route merge"
assert_eq "" "$(cli status --current)" "build#workflow-progress: a merged plan no longer appears on resume" || exit 1
cli status "$route" --json | python3 -c '
import json, sys
view = json.load(sys.stdin)["workflow"]
assert view["stage"] == "finish" and not view["actions"], view
assert view["stages"][-1]["state"] == "complete", view
' || fail "build#workflow-progress: the merged route is terminal"

gate_fixture() {
  cd "$(mktemp_dir)" || exit 1
  git init -q -b main
  mkdir -p "$plans" src
  echo base > src/a
  git add src && git commit -q -m base || fail 'fixture base'
  route="$plans/2026-11-25-evidence.md"
  mkp "$route" evidence ''
  edit "$route" 'Gate: small' "Gate: $1"
  edit "$route" $'1. a → b\n\n## Spec' $'1. a → b\n2. c → d\n\n## Spec'
  if [ "${3:-}" = human ]; then
    edit "$route" $'1. a → b\n2. c → d' $'1. a → b — you check\n2. c → d — you check'
  fi
  edit "${route%.md}.run.toml" 'full = ["scripts/check", "scripts/test"]' "full = [\"$2\"]"
  cat >> "${route%.md}.run.toml" <<'TOML'
[executors.fixture.primary]
model = "first"
[executors.fixture.secondary]
model = "followup"
TOML
  approve_plan "$route" >/dev/null || fail 'approve fixture'
  cli build start "$route" --base main >/dev/null || fail 'start fixture'
  cli phase start "$route" 1 >/dev/null || fail 'start fixture phase'
  commit_fixture implementation
  report_phase "$route" 1 --became fixture --commit "$(git rev-parse HEAD)" >/dev/null || fail 'report fixture phase'
  cli phase done "$route" 1 >/dev/null || fail 'finish fixture phase'
  cli gate start "$route" >/dev/null || fail 'start fixture gate'
}

commit_fixture() {
  printf '%s\n' "$1" >> src/a
  git commit -q -m "$1" -- src/a || fail "commit $1"
}

next_actions() {
  cli status "$route" --json | python3 -c 'import json, sys; print(*(a["action"] for a in json.load(sys.stdin)["workflow"]["actions"]), sep="\n")'
}

failed=0
(
  # build#review-completion: a fix racing the first review cannot leave the implementation unreviewed.
  gate_fixture small 'grep -q fixed src/a'
  first_head=$(git rev-parse HEAD)
  base=$(git rev-parse main)
  first_brief=$(cli brief reviewer "$route" --provider fixture) || fail 'dispatch initial reviewer'
  if next_actions | grep -q 'fix start'; then fail 'build#review-completion: status must wait for initial review before suggesting a fix'; fi
  cli fix start "$route" >/dev/null || fail 'open fix before review reply'
  commit_fixture fixed
  tip=$(git rev-parse HEAD)
  cli fix report "$route" --became fixed --commit "$tip" >/dev/null || fail 'report fixture fix'
  cli fix done "$route" >/dev/null || fail 'finish fixture fix'
  out=$(cli review complete "$route" --assignment gate --range "$base..$first_head"); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: late reviewer cannot attest to the new tip' || exit 1
  out=$(cli review complete "$route" --assignment gate-fix-1 --range "$first_head..$tip"); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: the fix range alone cannot cover the implementation' || exit 1
  brief=$(cli brief reviewer "$route" --provider fixture) || fail 'brief recovered reviewer'
  assert_contains "$(cat "$brief")" "Range: $base..$tip" 'build#review-completion: recovered assignment includes the implementation' || exit 1
  assert_contains "$(cat "$brief")" 'Executor tier: primary' 'build#review-completion: recovered first review uses primary' || exit 1
  assert_contains "$(cat "$first_brief")" "Range: $base..$first_head" 'build#review-completion: the first reviewer retains the original brief' || exit 1
  complete_review "$route" --provider fixture || fail 'record full review after fix'
  cli verdict pass "$route" --predicted pass --engine fixture --report reviewed >/dev/null || fail 'pass reviewed fixture'
) || failed=1
(
  # build#review-completion: same-tree commits preserve captures, but start a new pre-land review.
  gate_fixture normal true
  complete_review "$route" --provider fixture || fail 'complete first review'
  cli result "$route" --case 1 --outcome passed --capture first >/dev/null || fail 'record first capture'
  cli result "$route" --case 2 --outcome passed --capture second >/dev/null || fail 'record second capture'
  cli verdict pass "$route" --predicted pass --engine fixture --report reviewed >/dev/null || fail 'pass initial tip'
  git commit -q --allow-empty -m 'same tree at a new tip' || fail 'commit on same tree'
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: a same-tree commit still needs its exact review' || exit 1
  assert_contains "$out" 'review-missing' 'build#review-completion: the outstanding evidence is review' || exit 1
  cli land draft "$route" >/dev/null || fail 'draft land shape'
  out=$(cli land "$route"); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: the old verdict cannot land a different commit history' || exit 1
  assert_contains "$out" 'judge-stale' 'build#review-completion: land refuses the stale verdict' || exit 1
  brief=$(cli brief reviewer "$route" --provider fixture) || fail 'brief same-tree reviewer'
  assert_contains "$(cat "$brief")" "Range: $(git rev-parse main)..$(git rev-parse HEAD)" 'build#review-completion: same-tree reviewer sees the new tip' || exit 1
  complete_review "$route" --provider fixture || fail 'record exact same-tree review'
  cli brief judge "$route" --provider fixture >/dev/null || fail 'build#review-completion: existing same-tree captures remain applicable'
) || failed=1
(
  # build#workflow-progress: each published role command accepts the run's provider.
  gate_fixture normal true
  actions=$(next_actions)
  assert_contains "$actions" 'brief reviewer --provider PROVIDER <plan>' 'build#workflow-progress: status binds the reviewer provider' || exit 1
  assert_contains "$actions" 'brief verify --provider PROVIDER <plan>' 'build#workflow-progress: status binds the Verify provider' || exit 1
  typed_action "$route" build-verification work Reviewer 'brief reviewer' '{"executor":{"provider":"fixture","source":"approved run snapshot","tier":"primary","model":"first"}}' inspect --provider fixture
  typed_action "$route" build-verification work Verify 'brief verify' '{"executor":{"provider":"fixture","source":"approved run snapshot","tier":"secondary","model":"followup"}}' inspect --provider fixture
  typed_action "$route" build-verification run Coordinator 'brief reviewer' '{}' run --provider fixture
  typed_action "$route" build-verification run Coordinator 'brief verify' '{}' run --provider fixture
  complete_review "$route" --provider fixture || fail 'complete provider fixture review'
  assert_contains "$(next_actions)" 'brief judge --provider PROVIDER <plan> --note REASON' 'build#workflow-progress: E2E exception includes a provider' || exit 1
  cli result "$route" --case 1 --outcome passed --capture first >/dev/null || fail 'record first case'
  cli result "$route" --case 2 --outcome passed --capture second >/dev/null || fail 'record second case'
  assert_contains "$(next_actions)" 'brief judge --provider PROVIDER <plan>' 'build#workflow-progress: ready judge includes a provider' || exit 1
  typed_action "$route" build-verification ask Coordinator 'provider'
  typed_action "$route" build-verification run Coordinator 'brief judge' '{}' run --provider fixture
  typed_action "$route" build-verification ask Coordinator 'approved run snapshot' '{}' inspect --provider missing
  cli verdict question "$route" --predicted pass --engine fixture --report 'need input' --question 'Is this right?' >/dev/null || fail 'ask fixture question'
  assert_contains "$(next_actions)" 'brief judge --provider PROVIDER <plan> --note ANSWER' 'build#workflow-progress: judge question includes a provider' || exit 1
) || failed=1
(
  # build#workflow-progress: an owed recapture remains assigned until that case is recorded again.
  gate_fixture normal true
  complete_review "$route" --provider fixture || fail 'complete evidence fixture review'
  cli result "$route" --case 1 --outcome passed --capture first >/dev/null || fail 'record first case'
  cli result "$route" --case 2 --outcome passed --capture second >/dev/null || fail 'record second case'
  cli verdict evidence-owed "$route" --owed verify --report 'Capture Done 1 again' >/dev/null || fail 'record judge recapture request'
  if next_actions | grep -q 'Issue `brief judge'; then fail 'build#workflow-progress: status must wait for the owed recapture'; fi
  cli verdict evidence-owed "$route" --owed verify --case 2 --report 'Capture the other case' >/dev/null || fail 'request a second recapture'
  cli result "$route" --case 2 --outcome passed --capture unrelated >/dev/null || fail 'record unrelated capture'
  route_step build-verification Verify 'Capture Done 1 again'
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 1 "$rc" 'build#workflow-progress: earlier captures do not satisfy a requested recapture' || exit 1
  assert_contains "$out" 'Done 1 lacks current E2E evidence' 'build#workflow-progress: the refused brief identifies the owed case' || exit 1
  cli result "$route" --case 1 --outcome passed --capture relevant >/dev/null || fail 'record owed capture'
  route_step build-verification Coordinator 'brief judge'
  if next_actions | grep -q 'Capture Done 1 again'; then fail 'build#workflow-progress: fulfilled recapture no longer needs action'; fi
  cli verdict evidence-owed "$route" --owed reviewer --report 'Review the range again' >/dev/null || fail 'record review request'
  cli result "$route" --case 1 --outcome passed --capture unrelated >/dev/null || fail 'record unrelated result'
  route_step build-verification Reviewer 'Review the range again'
  complete_review "$route" --provider fixture || fail 'record owed review'
  route_step build-verification Coordinator 'brief judge'
  cli verdict evidence-owed "$route" --owed verify --case 2 --report 'New screenshot requested' >/dev/null || fail 'scope evidence request explicitly'
  route_step build-verification Verify 'brief verify --provider PROVIDER <plan> --cases 2'
  cli verdict pass "$route" --predicted pass --engine fixture --report 'Existing case reviewed' --evidence-note 'Second capture unavailable in the fixture' >/dev/null || fail 'record explicit resolution'
  route_step judge Judge 'land draft'
) || failed=1
(
  # build#review-completion: independent requests survive until fresh, matching evidence or an E2E exception.
  gate_fixture normal true
  complete_review "$route" --provider fixture || fail 'complete initial review'
  cli result "$route" --case 1 --outcome passed --capture first >/dev/null || fail 'record first case'
  cli result "$route" --case 2 --outcome passed --capture second >/dev/null || fail 'record second case'
  cli verdict evidence-owed "$route" --owed reviewer --report 'Revisit the review' >/dev/null || fail 'request new review'
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: the older completion cannot meet a fresh review request' || exit 1
  assert_contains "$out" 'review-missing' 'build#review-completion: the refusal names review' || exit 1
  cli verdict evidence-owed "$route" --owed verify --case 1 --report 'Recapture the first case' >/dev/null || fail 'request first case'
  cli verdict evidence-owed "$route" --owed verify --case 2 --report 'Recapture the second case' >/dev/null || fail 'request second case'
  route_step build-verification Reviewer 'Revisit the review'
  route_step build-verification Verify 'Recapture the first case'
  route_step build-verification Verify 'Recapture the second case'
  brief=$(cli brief verify "$route" --provider fixture) || fail 'brief both requested cases'
  assert_contains "$(cat "$brief")" '1. a → b' 'build#review-completion: Verify gets the first case' || exit 1
  assert_contains "$(cat "$brief")" '2. c → d' 'build#review-completion: Verify gets the second case' || exit 1
  cli result "$route" --case 2 --outcome passed --capture new-second >/dev/null || fail 'recapture second case'
  out=$(cli verdict pass "$route" --predicted pass --engine fixture --report premature --evidence-note 'Waive capture'); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: an E2E exception cannot waive a review request' || exit 1
  assert_contains "$out" 'review-missing' 'build#review-completion: the verdict needs the new review' || exit 1
  complete_review "$route" --provider fixture || fail 'complete requested review'
  route_step build-verification Verify 'Recapture the first case'
  if next_actions | grep -Eq 'Revisit the review|Recapture the second case|Issue `brief judge'; then fail 'build#review-completion: only first recapture and its exception remain'; fi
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: the first request still gates the brief' || exit 1
  assert_contains "$out" 'Done 1 lacks current E2E evidence' 'build#review-completion: the brief names only the remaining requested case' || exit 1
  out=$(cli verdict pass "$route" --predicted pass --engine fixture --report premature); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: the first request still gates the verdict' || exit 1
  assert_contains "$out" 'Done 1 lacks current E2E evidence' 'build#review-completion: the verdict names only the remaining requested case' || exit 1
  cli result "$route" --case 1 --outcome passed --capture new-first >/dev/null || fail 'recapture first case'
  cli brief judge "$route" --provider fixture >/dev/null || fail 'all requests satisfied by matching evidence'
  cli verdict evidence-owed "$route" --owed verify --case 1 --report 'Capture first again' >/dev/null || fail 'request first again'
  cli verdict evidence-owed "$route" --owed verify --case 2 --report 'Capture second again' >/dev/null || fail 'request second again'
  route_step build-verification Coordinator 'brief judge --provider PROVIDER <plan> --note REASON'
  cli brief judge "$route" --provider fixture --note 'Fixture has no new captures' >/dev/null || fail 'brief with explicit exception'
  cli verdict pass "$route" --predicted pass --engine fixture --report 'Reviewed with exception' --evidence-note 'Fixture has no new captures' >/dev/null || fail 'record explicit resolution of both requests'
  route_step judge Judge 'land draft'
  cli brief judge "$route" --provider fixture >/dev/null || fail 'resolved requests no longer gate a new brief'
  assert_contains "$(cli status "$route")" 'owed by verify: Capture first again' 'build#review-completion: the request history is retained' || exit 1
) || failed=1
(
  # build#review-completion: the result shown to the judge determines whether a requested capture is present.
  gate_fixture normal true
  complete_review "$route" --provider fixture || fail 'complete review before recaptures'
  cli verdict evidence-owed "$route" --owed verify --case 1 --case 2 --report 'Recapture both cases' >/dev/null || fail 'request both recaptures'
  cli result "$route" --case 1 --outcome passed --capture superseded >/dev/null || fail 'recapture first case'
  cli result "$route" --case 1 --outcome not-reached --detail 'Fixture stopped before the capture' >/dev/null || fail 'replace first result'
  cli result "$route" --case 2 --outcome passed --capture second >/dev/null || fail 'recapture second case'
  out=$(cli verdict pass "$route" --predicted pass --engine fixture --report premature); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: a superseded capture cannot satisfy a recapture' || exit 1
  assert_contains "$out" 'Done 1 lacks current E2E evidence' 'build#review-completion: the verdict names the case still owed' || exit 1
  route_step build-verification Verify 'brief verify --provider PROVIDER <plan> --cases 1'
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 1 "$rc" 'build#review-completion: the judge brief also requires the outstanding recapture' || exit 1
  assert_contains "$out" 'Done 1 lacks current E2E evidence' 'build#review-completion: the brief names the case still owed' || exit 1
  cli result "$route" --case 1 --outcome passed --capture first >/dev/null || fail 'record current first capture'
  cli brief judge "$route" --provider fixture >/dev/null || fail 'current captures fulfill both requests'
  cli verdict pass "$route" --predicted pass --engine fixture --report reviewed >/dev/null || fail 'pass after both current captures'
) || failed=1
(
  # build#workflow-progress: a small gate's explicit Verify request can be fulfilled through the cases in its brief.
  gate_fixture small true
  complete_review "$route" --provider fixture || fail 'complete small-gate review'
  cli verdict evidence-owed "$route" --owed verify --report 'Recapture all assigned cases' >/dev/null || fail 'request assigned cases'
  brief=$(cli brief verify "$route" --provider fixture) || fail 'brief the assigned cases'
  assert_contains "$(cat "$brief")" '1. a → b' 'build#workflow-progress: the first assigned case is in the brief' || exit 1
  assert_contains "$(cat "$brief")" '2. c → d' 'build#workflow-progress: the second assigned case is in the brief' || exit 1
  cli result "$route" --case 1 --outcome passed --capture first >/dev/null || fail 'recapture first assigned case'
  cli result "$route" --case 2 --outcome passed --capture second >/dev/null || fail 'recapture second assigned case'
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 0 "$rc" "build#workflow-progress: fresh captures fulfill the unscoped small-gate request ($out)" || exit 1
  route_step build-verification Coordinator 'Issue `brief judge'
  if next_actions | grep -q 'Recapture all assigned cases'; then fail 'build#workflow-progress: the fulfilled request leaves no work for Verify'; fi
) || failed=1
(
  # build#workflow-progress: a Verify request with zero assigned cases has an explicit resolution.
  gate_fixture small true human
  complete_review "$route" --provider fixture || fail 'complete small-gate review'
  cli verdict evidence-owed "$route" --owed verify --report 'Recapture all assigned cases' >/dev/null || fail 'request captures'
  route_step build-verification Coordinator 'No Done cases are assigned to Verify'
  if next_actions | grep -q 'brief verify'; then fail 'build#workflow-progress: zero assigned cases leave no work for Verify'; fi
  out=$(cli brief judge "$route" --provider fixture); rc=$?
  assert_eq 1 "$rc" 'build#workflow-progress: the judge must explicitly resolve an empty request' || exit 1
  assert_contains "$out" 'no assigned Done cases' 'build#workflow-progress: the refusal explains why no result can resolve the request' || exit 1
  cli brief judge "$route" --provider fixture --note 'Both cases require human review' >/dev/null || fail 'brief the judge with an explicit exception'
  cli verdict pass "$route" --predicted pass --engine fixture --report reviewed --evidence-note 'Both cases require human review' >/dev/null || fail 'resolve the empty request'
  route_step judge Judge 'land draft'
) || failed=1
(
  # build#checks-by-code: explicitly reusing a completed check switches back to its evidence.
  gate_fixture small true
  checked=$(git rev-parse HEAD)
  commit_fixture intervening
  cli gate start "$route" >/dev/null || fail 'check intervening tree'
  git reset -q --hard "$checked" || fail 'restore earlier fixture tree'
  out=$(cli gate start "$route") || fail 'reuse earlier check'
  assert_contains "$out" '(reused, run' 'build#checks-by-code: the earlier completed check is reused' || exit 1
  assert_contains "$(cli status "$route")" "Checks at ${checked:0:7}: green" 'build#checks-by-code: status shows the selected check' || exit 1
  if next_actions | grep -q 'Full checks are missing or stale'; then fail 'build#checks-by-code: reused check is the current evidence'; fi
  complete_review "$route" --provider fixture || fail 'build#checks-by-code: the reviewer can complete after reuse'
) || failed=1
(
  # build#review-completion: generated commits are in pinned fix and round ranges even after empty reports.
  gate_fixture small true
  cli finding "$route" --kind defect --where src/a:1 --source plan --text 'needs generated fix' >/dev/null || fail 'record fixture defect'
  complete_review "$route" --provider fixture || fail 'complete review before generated fix'
  cli fix start "$route" >/dev/null || fail 'open generated fix'
  from=$(git rev-parse HEAD)
  cli fix report "$route" --became 'No implementer changes' >/dev/null || fail 'record empty fix report'
  commit_fixture generated-fix
  cli fix done "$route" >/dev/null || fail 'finish fix with generated commit'
  brief=$(cli brief reviewer "$route" --provider fixture) || fail 'brief fix reviewer'
  assert_contains "$(cat "$brief")" "Range: $from..$(git rev-parse HEAD)" 'build#review-completion: the brief shows the actual nonempty fix range' || exit 1
  assert_contains "$(cat "$brief")" 'Executor tier: secondary' 'build#review-completion: the targeted fix review uses secondary' || exit 1
  complete_review "$route" --provider fixture || fail 'complete review before round'
  cli verdict round "$route" --predicted round --engine fixture --report round --note 'Review the generated change' bug >/dev/null || fail 'order round'
  cli round start "$route" >/dev/null || fail 'start round'
  from=$(git rev-parse HEAD)
  cli round report "$route" --became 'No implementer changes' >/dev/null || fail 'record empty round report'
  commit_fixture generated
  cli round done "$route" >/dev/null || fail 'finish round with generated commit'
  brief=$(cli brief reviewer "$route" --provider fixture) || fail 'brief round reviewer'
  assert_contains "$(cat "$brief")" "Range: $from..$(git rev-parse HEAD)" 'build#review-completion: the brief shows the actual nonempty round range' || exit 1
) || failed=1
[ "$failed" -eq 0 ] || exit 1

echo "pipeline.test.sh: ok"
